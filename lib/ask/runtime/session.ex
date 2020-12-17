defmodule Ask.Runtime.Session do
  import Ecto.Query
  import Ecto

  alias Ask.{
    Repo,
    QuotaBucket,
    Respondent,
    Schedule,
    RespondentDispositionHistory,
    Survey,
    Endpoint,
    UrlShortener
  }

  alias Ask.Runtime.Flow.TextVisitor

  alias Ask.Runtime.{
    Flow,
    Channel,
    Session,
    Reply,
    SurveyLogger,
    ReplyStep,
    SessionMode,
    SessionModeProvider,
    SMSMode,
    IVRMode,
    MobileWebMode,
    SMSSimulatorMode,
    MobilewebSimulatorMode,
    ChannelPatterns,
    RetriesHistogram
  }

  use Timex

  defstruct [:current_mode, :fallback_mode, :flow, :respondent, :token, :fallback_delay, :channel_state, :count_partial_results, :schedule]

  @doc """
    Starts a new session.
    Possible return patterns:
      - {:ok, session, reply, timeout}
      - {:end, reply, respondent}
  """
  def start(questionnaire, respondent, channel, mode, schedule, retries \\ [], fallback_channel \\ nil, fallback_mode \\ nil, fallback_retries \\ [], fallback_delay \\ nil, count_partial_results \\ false, persist \\ true) do
    flow = Flow.start(questionnaire, mode)
    session = %Session{
      current_mode: SessionModeProvider.new(mode, channel, retries),
      fallback_mode: SessionModeProvider.new(fallback_mode, fallback_channel, fallback_retries),
      flow: flow,
      respondent: update_section_order(respondent, flow.section_order, persist),
      fallback_delay: fallback_delay || Survey.default_fallback_delay(),
      count_partial_results: count_partial_results,
      schedule: schedule
    }
    run_flow(session, persist)
  end

  @doc """
    Timeouts the given session.
    This may mean: end the session, retry the current mode or switch to the fallback mode

    Possible return patterns:
      - {:ok, session, reply, timeout}
      - {:end, reply, respondent}
      - {:stalled, session, respondent}
      - {:failed, respondent}
  """
  def timeout(%{channel_state: channel_state} = session) do
    runtime_channel = Ask.Channel.runtime_channel(session.current_mode.channel)

    cond do
      Channel.has_queued_message?(runtime_channel, channel_state) ->
        {:ok, session, %Reply{}, current_timeout(session)}

      Channel.message_expired?(runtime_channel, channel_state) ->
        # do not retry since the respondent was never contacted, thus the retries should not be consumed
        session = contact_respondent(session, runtime_channel)

        next_available_date_time = session.schedule |> Schedule.next_available_date_time

        base_timeout = Interval.new(from: DateTime.utc_now, until: next_available_date_time)
                       |> Interval.duration(:minutes)

        {:ok, session, %Reply{}, base_timeout + current_timeout(session)}
      true ->
        timeout(session, runtime_channel)
    end
  end

  def timeout(%{current_mode: %{retries: []}, fallback_mode: nil} = session, _) do
    session = %{session | respondent: RetriesHistogram.remove_respondent(session.respondent)}
    terminate(session)
  end

  def timeout(%{current_mode: %{retries: []}} = session, _) do
    switch_to_fallback_mode(session)
  end

  def timeout(%Session{} = session, runtime_channel) do
    best_timeout_option = best_timeout_option(session)
    session = retry(session, runtime_channel)

    # The new session will timeout as defined by hd(retries)
    {:ok, session, %Reply{}, best_timeout_option || current_timeout(session)}
  end

  @doc """
    Synchronizes the given session with the given respondent's response

    Possible return patterns:
      - {:ok, session, reply, timeout}
      - {:stopped, reply, respondent}
      - {:hangup, session, reply, timeout, respondent}
      - {:failed, respondent}
      - {:end, reply, respondent}
      - {:rejected, respondent}
      - {:rejected, session, reply, timeout}
      - {:rejected, reply, respondent}
  """
  def sync_step(session, response) do
    sync_step(session, response, session.current_mode)
  end

  def sync_step(session, response, current_mode, persist \\ true, want_log_response \\ true) do
    if want_log_response do
      log_response(response, current_mode.channel, session.flow.mode, session.respondent, session.respondent.disposition)
    end
    session = cond do
      response == Flow.Message.no_reply ->
        # no_reply is produced, for example, from a timeout in Verboice
        session
      Flow.Message.is_stop_reply(response) ->
        # the user asked for stopping receiving messages
        session
      response == Flow.Message.answer ->
        update_respondent_disposition(session, "contacted", current_mode, persist)
      true ->
        update_respondent_disposition(session, "started", current_mode, persist)
    end
    respondent = session.respondent
    step_answer = Flow.step(session.flow, current_mode |> SessionMode.visitor, response, SessionMode.mode(current_mode), respondent.disposition)
                  |> relevant_interim_partial_step(respondent, persist)
    reply = case step_answer do
      {:end, _, reply} -> reply
      {:ok, _flow, reply} -> reply
      {:no_retries_left, _flow, reply} -> reply
      {:stopped, _flow, reply} -> reply
      _ -> %Reply{}
    end

    if Flow.should_update_disposition(respondent.disposition, reply.disposition) do
      log_disposition_changed(respondent, current_mode.channel, session.flow.mode, respondent.disposition, reply.disposition, persist)
    end

    respondent = store_responses_and_assign_bucket(respondent, step_answer, session, persist)

    session = %{session | respondent: respondent}
    session |> handle_step_answer(step_answer, current_mode, persist)
  end

  def update_section_order(respondent, nil, _), do: respondent

  def update_section_order(respondent, section_order, persist) do
    Respondent.update(respondent, %{section_order: section_order}, persist)
  end

  def current_timeout(%Session{current_mode: %{retries: []}, fallback_delay: fallback_delay}) do
    fallback_delay
  end

  def current_timeout(%Session{current_mode: %{retries: [next_retry | _]}}) do
    next_retry
  end

  def log_disposition_changed(respondent, channel, mode, previous_disposition, new_disposition, persist \\ true) do
    if persist do
      SurveyLogger.log(respondent.survey_id, mode, respondent.id, respondent.hashed_number, channel.id, previous_disposition, "disposition changed", String.capitalize(new_disposition))
    end
  end

  def contact_respondent(%{current_mode: %SMSMode{}} = session, runtime_channel) do
    token = Ecto.UUID.generate

    respondent = session.respondent
    {:ok, _flow, reply} = Flow.retry(session.flow, TextVisitor.new("sms"), respondent.disposition)
    log_prompts(reply, session.current_mode.channel, session.flow.mode, respondent)
    respondent = runtime_channel |> Channel.ask(session.respondent, token, reply)
    %{session | token: token, respondent: respondent}
  end

  def contact_respondent(%{schedule: schedule, current_mode: %IVRMode{}} = session, runtime_channel) do
    token = Ecto.UUID.generate

    next_available_date_time = schedule
                               |> Schedule.next_available_date_time

    today_end_time = schedule
                     |> Schedule.at_end_time(next_available_date_time)

    channel_state = runtime_channel
                    |> Channel.setup(session.respondent, token, next_available_date_time, today_end_time)
                    |> handle_setup_response()

    %{session | channel_state: channel_state, token: token}
  end

  def contact_respondent(%{current_mode: %MobileWebMode{}} = session, runtime_channel) do
    token = Ecto.UUID.generate

    reply = mobile_contact_reply(session)
    log_prompts(reply, session.current_mode.channel, session.flow.mode, session.respondent)
    respondent = runtime_channel |> Channel.ask(session.respondent, token, reply)
    %{session | token: token, respondent: respondent}
  end

  def channel_failed(%Session{current_mode: %{retries: []}, fallback_mode: nil} = session, reason) do
    log_contact(reason, session.current_mode.channel, session.flow.mode, session.respondent)
    :failed
  end

  def channel_failed(session, reason) do
    log_contact(reason, session.current_mode.channel, session.flow.mode, session.respondent)
    :ok
  end

  def contact_attempt_expired(session) do
    runtime_channel = Ask.Channel.runtime_channel(session.current_mode.channel)

    session = contact_respondent(session, runtime_channel)

    next_available_date_time = session.schedule |> Schedule.next_available_date_time

    base_timeout = Interval.new(from: DateTime.utc_now, until: next_available_date_time)
                   |> Interval.duration(:minutes)

    {:ok, session, base_timeout + current_timeout(session)}
  end

  def delivery_confirm(session, title, current_mode, persist) do
    if persist, do: log_confirmation(title, session.respondent.disposition, current_mode.channel, session.flow.mode, session.respondent)
    update_respondent_disposition(session, "contacted", current_mode, persist)
  end

  def cancel(session) do
    Ask.Channel.runtime_channel(session.current_mode.channel)
    |> Channel.cancel_message(session.channel_state)
  end

  def dump(session) do
    %{
      current_mode: session.current_mode |> SessionModeProvider.dump,
      fallback_mode: session.fallback_mode |> SessionModeProvider.dump,
      flow: session.flow |> Flow.dump,
      respondent_id: session.respondent.id,
      token: session.token,
      fallback_delay: session.fallback_delay,
      channel_state: session.channel_state,
      count_partial_results: session.count_partial_results,
      schedule: session.schedule |> Schedule.dump!
    }
  end

  def load(state) do
    %Session{
      current_mode: SessionModeProvider.load(state["current_mode"]),
      fallback_mode: SessionModeProvider.load(state["fallback_mode"]),
      flow: Flow.load(state["flow"]),
      respondent: Repo.get(Ask.Respondent, state["respondent_id"]),
      token: state["token"],
      fallback_delay: state["fallback_delay"],
      channel_state: state["channel_state"],
      count_partial_results: state["count_partial_results"],
      schedule: state["schedule"] |> Schedule.load!
    }
  end

  def load_respondent_session(%Ask.Respondent{} = respondent, persist) do
    if(persist) do
      load(respondent.session)
    else
      respondent.session
    end
  end

  def current_step_index(session) do
    session.flow.current_step
  end

  def current_step_id(session) do
    flow = session.flow
    if flow && flow.current_step do
      Flow.current_step(flow)["id"]
    else
      nil
    end
  end

  defp mode_start(%Session{flow: flow, respondent: respondent, token: token, current_mode: %SMSMode{channel: channel}} = session) do
    runtime_channel = Ask.Channel.runtime_channel(channel)

    # Is this really necessary?
    Channel.setup(runtime_channel, respondent, token, nil, nil)

    case flow |> Flow.step(session.current_mode |> SessionMode.visitor, :answer, respondent.disposition) do
      {:end, _, reply} ->
        respondent = if Reply.prompts(reply) != [] do
          log_prompts(reply, channel, flow.mode, respondent, true)
          runtime_channel |> Channel.ask(respondent, token, reply)
        else
          respondent
        end
        {:end, reply, respondent}
      {:ok, flow, reply} ->
        if Flow.should_update_disposition(respondent.disposition, reply.disposition) do
          log_disposition_changed(respondent, channel, flow.mode, respondent.disposition, reply.disposition)
        end
        log_prompts(reply, channel, flow.mode, respondent)
        respondent = runtime_channel |> Channel.ask(respondent, token, reply)
        {:ok, %{session | flow: flow, respondent: respondent}, reply, current_timeout(session)}
    end
  end

  defp mode_start(%Session{current_mode: %SMSSimulatorMode{}} = session) do
    mode_start_simulation(session)
  end

  defp mode_start(%Session{current_mode: %MobilewebSimulatorMode{}} = session) do
    mode_start_simulation(session)
  end

  defp mode_start(%Session{flow: flow, current_mode: %IVRMode{channel: channel}, respondent: respondent, token: token, schedule: schedule} = session) do
    next_available_date_time = schedule
      |> Schedule.next_available_date_time

    today_end_time = schedule
      |> Schedule.at_end_time(next_available_date_time)

    channel_state = channel
      |> Ask.Channel.runtime_channel
      |> Channel.setup(respondent, token, next_available_date_time, today_end_time)
      |> handle_setup_response

    log_contact("Enqueueing call", channel, flow.mode, respondent)

    session = %{session| channel_state: channel_state}

    {:ok, %{session | respondent: respondent}, %Reply{}, current_timeout(session)}
  end

  defp mode_start(%Session{flow: flow, respondent: respondent, token: token, current_mode: %MobileWebMode{channel: channel}} = session) do
    runtime_channel = Ask.Channel.runtime_channel(channel)

    # Is this really necessary?
    Channel.setup(runtime_channel, respondent, token, nil, nil)

    reply = mobile_contact_reply(session)

    log_prompts(reply, session.current_mode.channel, flow.mode, session.respondent)
    respondent = runtime_channel
    |> Channel.ask(respondent, token, reply)

    {:ok, %{session | flow: flow, respondent: respondent}, reply, current_timeout(session)}
  end

  defp mode_start_simulation(%Session{flow: flow, respondent: respondent, current_mode: current_mode} = session) do
    case flow |> Flow.step(current_mode  |> SessionMode.visitor, :answer, respondent.disposition) do
      {:end, _, reply} ->
        {:end, reply, respondent}
      {:ok, flow, reply} ->
        {:ok, %{session | flow: flow, respondent: respondent}, reply, current_timeout(session)}
    end
  end

  defp retry(session, runtime_channel) do
    session
    |> add_session_mode_attempt!()
    |> contact_respondent(runtime_channel)
    |> consume_retry()
    |> RetriesHistogram.retry
  end

  # If the respondent has answered at least `min_relevant_steps` relevant steps
  # and the reply doesn't defines already a disposition
  # then, 'interim partial' disposition is returned in reply
  defp relevant_interim_partial_step({:ok, flow, %{disposition: nil} = reply} = step_answer, %{disposition: "started"} = respondent, persist) do
    new_step_answer = if Flow.interim_partial_by_relevant_steps?(flow) do # Filtered here to avoid fetching the responses unnecessarily
      valid_relevant_responses = all_responses(respondent, reply, persist) |> Enum.count(&Flow.relevant_response?(flow, &1))
      if valid_relevant_responses >= Flow.min_relevant_steps(flow) do
        {:ok, flow, %{reply | disposition: "interim partial"}}
      end
    end

    new_step_answer || step_answer
  end

  defp relevant_interim_partial_step(step_answer, _respondent, _persist), do: step_answer

  defp all_responses(respondent, reply, persist) do
    current_responses = Ask.Response.build_from_reply(reply)
    current_responses ++ Respondent.stored_responses(respondent, persist)
  end

  defp mobile_contact_reply(session) do
    %Reply{
      steps: [
        ReplyStep.new(
          mobile_contact_message(session),
          "Contact")
      ]
    }
  end

  def mobile_contact_message(%Session{flow: flow, respondent: respondent}) do
    msg = flow.questionnaire.settings["mobile_web_sms_message"] || "Please enter"
    prompts = Ask.Runtime.Step.split_by_newlines(msg)

    prompts
    |> Enum.with_index(1)
    |> Enum.map(fn {prompt, index} ->
      if index == length(prompts) do
       "#{prompt} #{mobile_web_url(respondent.id)}"
      else
       prompt
      end
    end)
  end

  defp mobile_web_url(respondent_id) do
    base_url = System.get_env("MOBILE_WEB_BASE_URL") || Endpoint.url
    UrlShortener.shorten_or_log_error("#{base_url}/mobile/#{respondent_id}?token=#{Respondent.token(respondent_id)}")
  end

  defp run_flow(%{current_mode: current_mode, respondent: respondent} = session, persist) do
    respondent = apply_patterns_if_match(current_mode.channel.patterns, respondent)
    add_mode_attempt = fn session -> if(persist) do add_session_mode_attempt!(session) else session end end

    session = %{session | token: Ecto.UUID.generate, respondent: respondent}
              |> add_mode_attempt.()
    mode_start(session)
  end

  defp apply_patterns_if_match(patterns, respondent) do
    canonical_number_as_list = respondent.canonical_phone_number |> String.graphemes
    matching_patterns = ChannelPatterns.matching_patterns(patterns, canonical_number_as_list)
    case matching_patterns do
      [] -> respondent
      [p | _] ->
        sanitized_phone_number = ChannelPatterns.apply_pattern(p, canonical_number_as_list)
        {:ok, updated_respondent} = respondent |> Respondent.changeset(%{sanitized_phone_number: sanitized_phone_number}) |> Repo.update
        updated_respondent
    end
  end

  defp log_prompts(reply, channel, mode, respondent, force \\ false, persist \\ true) do
    if persist do
      if force || !(channel |> Ask.Channel.runtime_channel |> Channel.has_delivery_confirmation?) do
        disposition = Reply.disposition(reply) || respondent.disposition
        Enum.each Reply.steps(reply), fn(step) ->
          step.prompts |> Enum.with_index |> Enum.each(fn {_prompt, index} ->
            SurveyLogger.log(
              respondent.survey_id,
              mode,
              respondent.id,
              respondent.hashed_number,
              channel.id,
              disposition,
              :prompt,
              ReplyStep.title_with_index(step, index + 1))
          end)
        end
      end
    end
  end

  defp log_confirmation(title, disposition, channel, mode, respondent) do
    SurveyLogger.log(respondent.survey_id, mode, respondent.id, respondent.hashed_number, channel.id, disposition, :prompt, title)
  end

  defp log_contact(status, channel, mode, respondent, disposition \\ nil) do
    SurveyLogger.log(respondent.survey_id, mode, respondent.id, respondent.hashed_number, channel.id, disposition || respondent.disposition, :contact, status)
  end

  defp log_response(:answer, channel, mode, respondent, disposition) do
    log_contact("Answer", channel, mode, respondent, disposition)
  end

  defp log_response(:no_reply, channel, mode, respondent, disposition) do
    log_contact("Timeout", channel, mode, respondent, disposition)
  end

  defp log_response({:reply, response}, channel, mode, respondent, disposition) do
    SurveyLogger.log(respondent.survey_id, mode, respondent.id, respondent.hashed_number, channel.id, disposition || respondent.disposition, :response, response)
  end

  defp log_response({:reply_with_step_id, response, _step_id}, channel, mode, respondent, disposition) do
    log_response({:reply, response}, channel, mode, respondent, disposition)
  end

  defp handle_setup_response(setup_response) do
    case setup_response do
      {:ok, new_state} ->
        new_state
      _ ->
        # TODO: handle Channel.setup errors
        nil
    end
  end

  defp clear_token(session) do
    %{session | token: nil}
  end

  defp best_timeout_option(%{current_mode: %{retries: retries}, fallback_mode: nil}) when length(retries) == 1, do: hd(retries)

  defp best_timeout_option(_), do: nil

  defp terminate(%{current_mode: %SMSMode{}, respondent: respondent}) do
    {:failed, respondent}
  end

  defp terminate(%{current_mode: %IVRMode{}, respondent: respondent}) do
    {:failed, respondent}
  end

  defp terminate(%{current_mode: %MobileWebMode{}, respondent: respondent}) do
    {:failed, respondent}
  end

  defp switch_to_fallback_mode(%{fallback_mode: fallback_mode, flow: flow} = session) do
    session = session |> clear_token
    run_flow_result = run_flow(%Session{
      session |
      current_mode: fallback_mode,
      fallback_mode: nil,
      channel_state: nil,
      flow: %{
        flow |
        mode: fallback_mode |> SessionMode.mode
      }
    }, true) # always persist changes since timeouts only happens in real flow
    result = case run_flow_result do
      {:ok, session, _, _} -> put_elem(run_flow_result, 1, RetriesHistogram.retry(session))
      _ -> run_flow_result
    end
    result
  end

  defp consume_retry(%{current_mode: %{retries: [_ | retries]}} = session) do
    %{session | current_mode: %{session.current_mode | retries: retries}}
  end

  defp consume_retry(%{current_mode: %{retries: []}} = session) do
    session
  end

  defp add_session_mode_attempt!(%Session{} = session), do: %{session | respondent: add_respondent_mode_attempt!(session)}

  defp add_respondent_mode_attempt!(%Session{respondent: respondent, current_mode: %SMSMode{}}), do: respondent |> Respondent.add_mode_attempt!(:sms)
  defp add_respondent_mode_attempt!(%Session{respondent: respondent, current_mode: %IVRMode{}}), do: respondent |> Respondent.add_mode_attempt!(:ivr)
  defp add_respondent_mode_attempt!(%Session{respondent: respondent, current_mode: %MobileWebMode{}}), do: respondent |> Respondent.add_mode_attempt!(:mobileweb)

  defp handle_step_answer(session, {:end, _, reply}, current_mode, persist) do
    log_prompts(reply, current_mode.channel, session.flow.mode, session.respondent, true, persist)
    {:end, reply, session.respondent}
  end

  defp handle_step_answer(session, {:ok, flow, reply}, current_mode, persist) do
    case must_be_rejected?(
           session.respondent.quota_bucket_id,
           session.respondent.disposition,
           reply.disposition,
           flow.in_quota_completed_steps,
           session.count_partial_results
         ) do
      true ->
        session = update_respondent_disposition(session, "rejected", current_mode)

        if flow.questionnaire.quota_completed_steps && length(flow.questionnaire.quota_completed_steps) > 0 do
          flow = %{flow | current_step: nil, in_quota_completed_steps: true}
          session = %{session | flow: flow}
          case sync_step(session, :answer, session.current_mode, persist, false) do
            {:ok, session, reply, timeout} ->
              {:rejected, session, reply, timeout}
            {:end, reply, respondent} ->
              {:rejected, reply, respondent}
            _ ->
              {:rejected, session.respondent}
          end
        else
          {:rejected, session.respondent}
        end
      false ->
        log_prompts(reply, current_mode.channel, flow.mode, session.respondent, false, persist)
        {:ok, %{session | flow: flow}, reply, current_timeout(session)}
    end
  end

  defp handle_step_answer(session, {:no_retries_left, flow, reply}, _, _) do
    case session do
      %{current_mode: %{retries: []}, fallback_mode: nil} ->
        {:failed, session.respondent}
      _ ->
        {:hangup, %{session | flow: flow}, reply, current_timeout(session), session.respondent}
    end
  end

  defp handle_step_answer(session, {:stopped, _, reply}, _current_mode, _) do
    {:stopped, reply, session.respondent}
  end

  defp store_responses_and_assign_bucket(respondent, {_, _, reply}, session, persist) do
    if persist do
      store_response(respondent, reply)
      try_to_assign_bucket(respondent, session)
    else
      updated_responses = respondent.responses ++ Ask.Response.build_from_reply(reply)
      %{respondent | responses: updated_responses}
    end
  end

  defp store_response(respondent, reply) do
    Reply.stores(reply) |> Enum.each(fn {field_name, value} ->
      existing_responses = respondent
      |> assoc(:responses)
      |> where([r], r.field_name == ^field_name)
      |> Repo.aggregate(:count, :id)

      if existing_responses == 0 do
        respondent
        |> Ecto.build_assoc(:responses, field_name: field_name, value: value)
        |> Repo.insert
      end
    end)
  end

  defp try_to_assign_bucket(respondent, session) do
    survey = (respondent |> Repo.preload(:survey)).survey

    buckets =
      case survey.quota_vars do
        [] -> []
        _ -> Repo.all(from q in QuotaBucket,
               where: q.survey_id == ^survey.id)
      end

    try_to_assign_bucket(respondent, buckets, session)
  end

  defp try_to_assign_bucket(respondent, [], _session) do
    respondent
  end

  defp try_to_assign_bucket(respondent, buckets, session) do
    if respondent.quota_bucket_id do
      respondent
    else
      respondent
        |> sorted_responses()
        |> buckets_matching_responses(buckets)
        |> assign_bucket_if_one_match(respondent, session)
    end
  end

  defp assign_bucket_if_one_match([bucket], respondent, session) do
    respondent =
    respondent |> Respondent.changeset(%{quota_bucket_id: bucket.id}) |> Repo.update!()

    # Runtime.Session increments by 1 the quota bucket when...
    # The respondent is already in a completed disposition and the quota bucket is assigned to them
    if Respondent.completed_disposition?(respondent.disposition, session.count_partial_results) do
      from(q in QuotaBucket, where: q.id == ^bucket.id) |> Repo.update_all(inc: [count: 1])
    end

    respondent
  end

  defp assign_bucket_if_one_match(_buckets, respondent, _session) do
    respondent
  end

  defp sorted_responses(respondent) do
    (respondent |> Repo.preload(:responses)).responses
      |> Enum.map(fn response ->
        {response.field_name, response.value}
      end) |> Enum.into([]) |> Enum.sort
  end

  defp buckets_matching_responses(responses, buckets) do
    buckets |> Enum.filter(fn bucket ->
      bucket.condition
        |> Map.to_list
        |> Enum.all?(fn {key, value} ->
          responses = responses |> Enum.filter(fn {response_key, _} -> response_key == key end)
          responses != []
            && responses
              |> Enum.all?(fn {_, response_value} ->
                response_value
                  |> QuotaBucket.matches_condition?(value)
              end)
        end)
    end)
  end

  # Must the respondent be rejected?
  defp must_be_rejected?(
         respondent_bucket_id,
         respondent_disposition,
         reply_disposition,
         in_quota_completed_steps,
         count_partial_results
       ) do
    # The respondent disposition is updated by Runtime.Survey after the current step is handled
    # by Runtime.Session, but the quota bucket could be assigned to the respondent and the quota
    # incremented before the disposition update happens. This is why if the disposition should be
    # updated both dispositions (repondent and reply) must be tested.
    inc_quota? = fn disposition ->
      Respondent.incremented_their_quota?(
        respondent_bucket_id,
        disposition,
        count_partial_results
      )
    end

    respondent_incremented_their_quota? =
      inc_quota?.(respondent_disposition) ||
        (Flow.should_update_disposition(respondent_disposition, reply_disposition) &&
           inc_quota?.(reply_disposition))

    cond do
      # Was the respondent already rejected?
      in_quota_completed_steps ->
        false

      # Is the respondent in a quota?
      respondent_bucket_id == nil ->
        false

      # Did the respondent increment their quota?
      respondent_incremented_their_quota? ->
        false

      # The above guards prevent the respondent to be considered rejectable during this test
      # If none of them apply then the respondent is rejected when their quota is completed
      true ->
        bucket = Repo.get!(QuotaBucket, respondent_bucket_id)
        bucket.count >= bucket.quota
    end
  end

  defp update_respondent_disposition(session, disposition, current_mode, persist \\ true) do
    respondent = session.respondent
    old_disposition = respondent.disposition
    if Flow.should_update_disposition(old_disposition, disposition) do
      respondent = Respondent.update(respondent, %{disposition: disposition}, persist)

      if(persist) do
        log_disposition_changed(respondent, current_mode.channel, session.flow.mode, old_disposition, disposition)
        RespondentDispositionHistory.create(respondent, old_disposition, session.current_mode |> SessionMode.mode)
      end

      %{session | respondent: respondent}
    else
      session
    end
  end
end
