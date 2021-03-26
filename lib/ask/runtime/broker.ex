defmodule Ask.Runtime.Broker do
  use GenServer
  import Ecto.Query
  import Ecto
  alias Ask.{Repo, Logger, Survey, Respondent, RespondentGroup, QuotaBucket, RespondentDispositionHistory, SystemTime, Schedule, SurvedaMetrics}
  alias Ask.Runtime.{Session, RetriesHistogram, ChannelStatusServer, SurveyAction}

  @poll_interval :timer.minutes(1)
  @server_ref {:global, __MODULE__}

  def server_ref, do: @server_ref

  def start_link do
    GenServer.start_link(__MODULE__, [], name: @server_ref)
  end

  # Makes the broker performs a poll on the surveys.
  # This method is intended to be used by tests.
  def poll do
    GenServer.call(@server_ref, :poll)
  end

  def init(_args) do
    :timer.send_after(1000, :poll)
    Logger.info "Broker started. Default batch size=#{default_batch_size()}. Limit per minute=#{batch_limit_per_minute()}."
    {:ok, nil}
  end

  def handle_info(:poll, state, now) do
    try do
      retry_respondents(now)
      poll_active_surveys(now)

      {:noreply, state}
    after
      :timer.send_after(@poll_interval, :poll)
    end
  end

  def handle_info(:poll, state) do
    handle_info(:poll, state, SystemTime.time.now)
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  def handle_call(:poll, _from, state) do
    handle_info(:poll, state)
    {:reply, :ok, state}
  end

  # visible for testing
  def retry_respondent(respondent) do
    session = respondent.session |> Session.load

    Repo.transaction(fn ->
      try do
        Ask.Runtime.Survey.handle_session_step(Session.timeout(session), SystemTime.time.now)
      rescue
        e ->
          Logger.error(e, "Error retrying respondent. Rolling back transaction")
          Repo.rollback(e)
      end
    end)
  end

  # visible for testing
  def configure_new_respondent(respondent, questionnaire_id, sequence_mode) do
    {primary_mode, _} = get_modes(sequence_mode)
    respondent
    |> Respondent.changeset(%{questionnaire_id: questionnaire_id, mode: sequence_mode, disposition: "queued"})
    |> Repo.update!
    |> RespondentDispositionHistory.create(respondent.disposition, primary_mode)
  end

  def poll_active_surveys(now) do
    all_running_surveys =
      Repo.all(
        from(s in Survey,
          where: s.state == "running",
          preload: [respondent_groups: [respondent_group_channels: :channel]]
        )
      )

    expired_surveys = Enum.filter(all_running_surveys, fn survey -> Survey.expired?(survey) end)
    expired_surveys_ids = Enum.map(expired_surveys, fn %{id: id} -> id end)

    Enum.filter(all_running_surveys, fn survey ->
      survey.id not in expired_surveys_ids and Schedule.intersect?(survey.schedule, now)
    end)
    |> Enum.each(fn survey -> poll_survey(survey, now) end)

    stop_surveys(expired_surveys)
  end

  defp stop_surveys(surveys) do
    Enum.map(surveys, fn survey -> stop_survey(survey) end)
  end

  def poll_survey(survey, now) do
    channels = survey |> Survey.survey_channels
    channel_is_down? = channels |> Enum.any?(fn c ->
      status = c.id |> ChannelStatusServer.get_channel_status
      (status != :up && status != :unknown)
    end)
    poll_survey(survey, now, channel_is_down?)
  end

  defp poll_survey(survey, _now, true = _channel_is_down) do
    ChannelStatusServer.log_info "Survey #{survey.id} was not polled because a channel is down"
  end

  defp poll_survey(survey, _now, false = _channel_is_down) do
    try do
      by_state = Survey.respondents_by_state(survey)
      %{
        "active" => active,
        "pending" => pending,
        "completed" => completed,
      } = by_state

      reached_quotas = reached_quotas?(survey)
      survey_completed = survey.cutoff <= completed || reached_quotas
      batch_size = batch_size(survey, by_state)
      survey = update_survey_on_poll(survey)
      Logger.info "Polling survey #{survey.id} (active=#{active}, pending=#{pending}, completed=#{completed}, batch_size=#{batch_size})"
      SurvedaMetrics.increment_counter_with_label(:surveda_survey_poll, [survey.id])

      cond do
        (active == 0 && (pending == 0 || survey_completed)) ->
          Logger.info "Survey #{survey.id} completed"
          complete(survey)

        active < batch_size && pending > 0 && !survey_completed ->
          count = batch_size - active
          Logger.info "Survey #{survey.id}. Starting up to #{count} respondents."
          start_some(survey, count)

        true -> :ok
      end
    rescue
      e ->
        handle_exception(survey, e, "Error occurred while polling survey (id: #{survey.id})")
    end
  end

  defp update_survey_on_poll(%{first_window_started_at: nil} = survey), do:
    Survey.changeset(survey, %{first_window_started_at: SystemTime.time.now}) |> Repo.update!

  defp update_survey_on_poll(survey), do: survey

  defp stop_survey(survey) do
    try do
      SurveyAction.stop(survey)
    rescue
      e ->
        handle_exception(survey, e, "Error occurred while stopping survey (id: #{survey.id})")
        Sentry.capture_exception(e, [
          stacktrace: System.stacktrace(),
          extra: %{survey_id: survey.id}])
    end
  end

  defp handle_exception(survey, e, message) do
    if Mix.env == :test do
      IO.inspect e
      IO.inspect System.stacktrace()
      raise e
    end
    Logger.error(e, message)
    Sentry.capture_exception(e, [
      stacktrace: System.stacktrace(),
      extra: %{survey_id: survey.id}])
  end

  defp retry_respondents(now) do
    Repo.all(from r in Respondent, select: r.id, where: r.state == "active" and r.timeout_at <= ^now, limit: ^batch_limit_per_minute())
    |> Enum.each(fn respondent_id -> Respondent.with_lock(respondent_id, &retry_respondent(&1)) end)
  end

  defp start(survey, respondent) do
    survey = Repo.preload(survey, [:questionnaires])
    group = respondent.respondent_group

    {questionnaire, mode} = select_questionnaire_and_mode(survey)

    {primary_mode, fallback_mode} = get_modes(mode)

    # Set respondent questionnaire and mode
    respondent = configure_new_respondent(respondent, questionnaire.id, mode)

    primary_channel = RespondentGroup.primary_channel(group, mode)
    fallback_channel = RespondentGroup.fallback_channel(group, mode)

    retries = Survey.retries_configuration(survey, primary_mode)
    fallback_retries = case fallback_channel do
      nil -> []
      _ -> Survey.retries_configuration(survey, fallback_mode)
    end

    fallback_delay = survey |> Survey.fallback_delay()
    SurvedaMetrics.increment_counter_with_label(:surveda_broker_respondent_start, [survey.id])
    Session.start(questionnaire, respondent, primary_channel, primary_mode, survey.schedule, retries, fallback_channel, fallback_mode, fallback_retries, fallback_delay, survey.count_partial_results)
    |> handle_session_started
    |> Ask.Runtime.Survey.handle_session_step(SystemTime.time.now)
  end

  defp default_batch_size do
    Survey.environment_variable_named(:batch_size)
  end

  defp reached_quotas?(survey) do
    case survey.quota_vars do
      [] -> false
      _ ->
        survey_id = survey.id
        Repo.one(from q in QuotaBucket,
                 where: q.survey_id == ^survey_id,
                 where: q.count < q.quota,
                 select: count(q.id)) == 0
    end
  end

  # Estimates the amount of respondents the broker will have to initiate contact with
  # to get the completed respondents needed.
  defp batch_size(survey, respondents_by_state) do
    case Survey.completed_respondents_needed_by(survey) do
      :all ->
        default_batch_size()

      respondents_target when is_integer(respondents_target) ->
        successful = Survey.completed_state_respondents(survey, respondents_by_state)
        estimated_success_rate = estimated_success_rate(survey, respondents_target)
        (respondents_target - successful) / estimated_success_rate
        |> trunc
    end
  end

  defp batch_limit_per_minute do
    Survey.environment_variable_named(:batch_limit_per_minute)
  end

  defp complete(survey) do
    Repo.update Survey.changeset(survey, %{state: "terminated", exit_code: 0, exit_message: "Successfully completed"})
  end

  defp start_some(survey, count) do
    count = Enum.min([batch_limit_per_minute(), count])

    (from r in assoc(survey, :respondents),
      select: r.id,
      where: r.state == "pending",
      limit: ^count)
    |> Repo.all
    |> Enum.each(fn respondent_id -> Respondent.with_lock(respondent_id, &start(survey, &1), &Repo.preload(&1, respondent_group: [respondent_group_channels: :channel])) end)
  end

  defp select_questionnaire_and_mode(%Survey{comparisons: []} = survey) do
    {hd(survey.questionnaires), hd(survey.mode)}
  end

  defp select_questionnaire_and_mode(%Survey{comparisons: comparisons} = survey) do
    # Get a random value between 0 and 100
    rand = :rand.uniform() * 100

    # Traverse comparisons:
    #
    # - keep the total ratio so far across visited comparisons
    # - included comparisons are those whose total ratio so far is greater than the rand value
    # - in the end we keep the first comparison that is included
    #
    # For example, if the ratios are [10, 25, 35, 30] and we
    # get a random value of 45, the result of the map_reduce will
    # be [{10, false}, {25, false}, {35, true}, {30, true}] because
    # after the entry with ratio 25 the total accumulated ratio will be
    # 10 + 25 + 35 = 70 >= 45. Then we keep the first one that's true.
    {candidates, _} = comparisons
                      |> Enum.map_reduce(0, fn (comparison, total_count) ->
      ratio = comparison["ratio"]
      total_count = total_count + (ratio || 0)
      included = total_count >= rand
      {{comparison, included}, total_count}
    end)

    candidate = candidates
                |> Enum.find(fn {_, included} -> included end)

    if candidate do
      {comparison, _} = candidate
      questionnaire = survey.questionnaires
                      |> Enum.find(fn q -> q.id == comparison["questionnaire_id"] end)
      mode = comparison["mode"]
      {questionnaire, mode}
    else
      # Fall back to first questionnaire and mode, in case
      # the comparisons ratios don't add up 100
      {hd(survey.questionnaires), hd(survey.mode)}
    end
  end

  defp get_modes(sequence_mode) do
    case sequence_mode do
      [primary] -> {primary, nil}
      [primary, fallback] -> {primary, fallback}
    end
  end

  defp handle_session_started(session_started)do
    case session_started do
      {:ok, session, reply, timeout} -> {:ok, %Session{session | respondent: RetriesHistogram.add_new_respondent(session.respondent, session, timeout)}, reply, timeout}
      other -> other
    end
  end

  defp estimated_success_rate(survey, respondents_target) do
    respondents_by_disposition = survey |> Survey.respondents_by_disposition
    completion_rate = Survey.get_completion_rate(survey, respondents_by_disposition, respondents_target)
    current_success_rate = Survey.get_success_rate(survey, respondents_by_disposition )
    initial_success_rate = Survey.initial_success_rate()
    Survey.estimated_success_rate(initial_success_rate, current_success_rate, completion_rate)
  end
end
