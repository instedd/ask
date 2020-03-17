defmodule Ask.Runtime.Respondent do
  use Timex
  import Ecto.Query
  import Ecto
  alias Ask.{Repo, Respondent, RespondentDispositionHistory, QuotaBucket, SystemTime}
  alias Ask.Runtime.{Session, Flow, SessionMode, SessionModeProvider, RetriesHistogram}

  def update_respondent(%Respondent{} = respondent, :end) do
    update_respondent(respondent, :end, nil, nil)
  end

  def update_respondent(%Respondent{} = respondent, {:stalled, session}) do
    respondent
    |> Respondent.changeset(%{state: "stalled", session: Session.dump(session), timeout_at: nil})
    |> Repo.update!
  end

  def update_respondent(%Respondent{} = respondent, :rejected) do
    respondent
    |> Respondent.changeset(%{state: "rejected", session: nil, timeout_at: nil})
    |> Repo.update!
  end

  def update_respondent(%Respondent{} = respondent, {:rejected, session, timeout}) do
    timeout_at = Respondent.next_actual_timeout(respondent, timeout, SystemTime.time.now)
    respondent
      |> Respondent.changeset(%{state: "rejected", session: Session.dump(session), timeout_at: timeout_at})
      |> Repo.update!
  end

  def update_respondent(%Respondent{} = respondent, :failed) do
    session = respondent.session |> Session.load
    mode = session.current_mode |> SessionMode.mode
    old_disposition = respondent.disposition
    new_disposition = Flow.failed_disposition_from(respondent.disposition)

    Session.log_disposition_changed(respondent, session.current_mode.channel, mode, old_disposition, new_disposition)

    respondent
    |> Respondent.changeset(%{state: "failed", session: nil, timeout_at: nil, disposition: new_disposition})
    |> Repo.update!
    |> RespondentDispositionHistory.create(old_disposition, mode)
  end

  def update_respondent(%Respondent{} = respondent, :stopped, disposition, _) do
    session = respondent.session |> Session.load
    update_respondent_and_set_disposition(respondent, session, nil, %{disposition: disposition, state: "failed", session: nil, timeout_at: nil, user_stopped: true})
  end

  def update_respondent(%Respondent{} = respondent, {:ok, session, timeout}, nil, now) do
    effective_modes = respondent.effective_modes || []
    effective_modes =
      if session do
        mode = Ask.Runtime.SessionMode.mode(session.current_mode)
        Enum.uniq(effective_modes ++ [mode])
      else
        effective_modes
      end

    timeout_at = Respondent.next_actual_timeout(respondent, timeout, now)
    respondent
    |> Respondent.changeset(%{state: "active", session: Session.dump(session), timeout_at: timeout_at, language: session.flow.language, effective_modes: effective_modes})
    |> Repo.update!
  end

  def update_respondent(%Respondent{} = respondent, {:ok, session, timeout}, disposition, _) do
    timeout_at = Respondent.next_actual_timeout(respondent, timeout, SystemTime.time.now)
    update_respondent_and_set_disposition(respondent, session, timeout, %{session: Session.dump(session), timeout_at: timeout_at, disposition: disposition, state: "active"})
  end

  def update_respondent(%Respondent{} = respondent, :end, reply_disposition, _) do
    [session, mode] = case respondent.session do
      nil -> [nil, nil]
      session ->
        session = session |> Session.load
        mode = session.current_mode |> SessionMode.mode
        [session, mode]
    end

    old_disposition = respondent.disposition

    new_disposition =
      old_disposition
      |> Flow.resulting_disposition(reply_disposition)
      |> Flow.resulting_disposition("completed")

    # If new_disposition == reply_disposition, change of disposition has already been logged during Session.sync_step
    if session && new_disposition != old_disposition && new_disposition != reply_disposition do
      Session.log_disposition_changed(respondent, session.current_mode.channel, mode, old_disposition, new_disposition)
    end

    respondent
    |> Respondent.changeset(%{state: "completed", disposition: new_disposition, session: nil, completed_at: SystemTime.time.now, timeout_at: nil})
    |> Repo.update!
    |> RespondentDispositionHistory.create(old_disposition, mode)
    |> update_quota_bucket(old_disposition, respondent.session["count_partial_results"])
  end

  def channel_failed(respondent, reason \\ "failed") do
    session = respondent.session
    if session do
      session = session |> Session.load
      case Session.channel_failed(session, reason) do
        :ok -> :ok
        :failed ->
          # respondent no longer participates in the survey (no attempts left)
          respondent = RetriesHistogram.remove_respondent(respondent)
          update_respondent(respondent, :failed)
      end
    else
      :ok
    end
  end

  def contact_attempt_expired(respondent) do
    session = respondent.session
    if session do
      response = session
                 |> Session.load
                 |> Session.contact_attempt_expired

      update_respondent(respondent, response, nil, SystemTime.time.now)
    end
    :ok
  end

  def delivery_confirm(respondent, title) do
    delivery_confirm(respondent, title, nil)
  end

  def delivery_confirm(respondent, title, mode) do
    unless respondent.session == nil do
      session = respondent.session |> Session.load
      session_mode =
        case session_mode(respondent, session, mode) do
          :invalid_mode -> session.current_mode
          mode -> mode
        end
      Session.delivery_confirm(session, title, session_mode)
    end
  end

  def session_mode(_respondent, session, nil) do
    session.current_mode
  end

  def session_mode(respondent, session, mode) do
    if mode == session.current_mode |> SessionMode.mode do
      session.current_mode
    else
      group = (respondent |> Repo.preload(:respondent_group)).respondent_group
      channel_group = (group |> Repo.preload([respondent_group_channels: :channel])).respondent_group_channels
                      |> Enum.find(fn c -> c.mode == mode end)

      if channel_group do
        SessionModeProvider.new(mode, channel_group.channel, [])
      else
        :invalid_mode
      end
    end
  end

  defp update_respondent_and_set_disposition(respondent, session, timeout, %{disposition: disposition} =  changes) do
    old_disposition = respondent.disposition
    if Flow.should_update_disposition(old_disposition, disposition) do
      respondent
      |> Respondent.changeset(changes)
      |> Repo.update!
      |> RespondentDispositionHistory.create(old_disposition, session.current_mode |> SessionMode.mode)
      |> update_quota_bucket(old_disposition, session.count_partial_results)
    else
      update_respondent(respondent, {:ok, session, timeout}, nil, SystemTime.time.now)
    end
  end

  defp update_quota_bucket(respondent, old_disposition, count_partial_results) do
    if should_update_quota_bucket(respondent.disposition, old_disposition, count_partial_results) do
      responses = respondent |> assoc(:responses) |> Repo.all
      matching_bucket = Repo.all(from b in QuotaBucket, where: b.survey_id == ^respondent.survey_id)
                      |> Enum.find( fn bucket -> match_condition(responses, bucket) end )

      if matching_bucket do
        from(q in QuotaBucket, where: q.id == ^matching_bucket.id) |> Ask.Repo.update_all(inc: [count: 1])
      end
    end
    respondent
  end

  defp should_update_quota_bucket(new_disposition, old_disposition, true) do
    (new_disposition != old_disposition && new_disposition == "interim partial")
    || (new_disposition == "completed" && old_disposition != "interim partial" && old_disposition != "completed")
  end

  defp should_update_quota_bucket(new_disposition, old_disposition, _) do
    new_disposition != old_disposition && new_disposition == "completed"
  end

  defp match_condition(responses, bucket) do
    bucket_vars = Map.keys(bucket.condition)

    Enum.all?(bucket_vars, fn var ->
      Enum.any?(responses, fn res ->
        (res.field_name == var) &&
          res.value |> QuotaBucket.matches_condition?(Map.fetch!(bucket.condition, var))
      end)
    end)
  end
end
