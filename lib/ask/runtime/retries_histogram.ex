defmodule Ask.Runtime.RetriesHistogram do
  alias Ask.{RetryStat, Stats, SystemTime, Logger, Respondent, Repo}
  alias Ask.Runtime.Session

  defp update_respondent(%Respondent{} = respondent, retry_stat_id),
    do:
      respondent
      |> Respondent.changeset(%{retry_stat_id: retry_stat_id})
      |> Repo.update!

  def add_new_respondent(respondent, session, timeout) do
    try do
      %Respondent{} = respondent
      %Session{} = session
      {:ok, retry_stat} = RetryStat.add(retry_stat_group(respondent, ivr?(session), timeout))
      update_respondent(respondent, retry_stat.id)
    rescue
      _ -> Logger.error("Error adding new respondent to histogram")
      respondent
    end
  end

  defp ivr?(%Session{current_mode: %Ask.Runtime.IVRMode{}}), do: true
  defp ivr?(_session), do: false

  defp retry_stat_group(%Respondent{stats: stats, mode: mode, survey_id: survey_id}, ivr_active?, timeout) do
    retry_time = Respondent.next_timeout_lowerbound(timeout, SystemTime.time.now) |> RetryStat.retry_time
    %{attempt: stats |> Stats.attempts(:all), mode: mode, retry_time: retry_time, ivr_active: ivr_active?, survey_id: survey_id}
  end

  def remove_respondent(respondent) do
    try do
      %Respondent{retry_stat_id: retry_stat_id} = respondent
      RetryStat.subtract(retry_stat_id)
      update_respondent(respondent, nil)
    rescue
      _ -> Logger.error("Error removing respondent from histogram")
      respondent
    end
  end

  defp reallocate_respondent(session, respondent, ivr_active?, timeout) do
    try do
      %Respondent{retry_stat_id: retry_stat_id} = respondent
      %Session{} = session
      {:ok, retry_stat} = RetryStat.transition(
        retry_stat_id,
        retry_stat_group(respondent, ivr_active?, timeout)
      )
      %Session{ session | respondent: update_respondent(respondent, retry_stat.id)}
    rescue
      _ ->
        Logger.error("Error reallocating respondent")
        session
    end
  end

  def next_step(respondent, %Session{current_mode: %Ask.Runtime.SMSMode{}} = session, {:reply, _reply}) do
    # sms -> transition to active RetryStat
    if respondent.retry_stat_id, do:
      reallocate_respondent(session, respondent, false, Session.current_timeout(session))
  end

  def next_step(_respondent, _session, {:reply, _reply}) do
    # ivr -> do nothing, respondent is on call
    # mobile-web -> do nothing
  end

  def next_step(respondent, _session, {:end, _reply}) do
    # remove respondent from histogram
    remove_respondent(respondent)
  end

  def next_step(respondent, _session, :end) do
    # remove respondent from histogram
    remove_respondent(respondent)
  end

  def respondent_no_longer_active(%{session: session} = respondent) do # only makes sense for verboice
    # transition from ivr active to normal retryStat
    session = Session.load(session)
    session = reallocate_respondent(session, respondent, false, Session.current_timeout(session))
    session.respondent
  end

  def retry(%{respondent: respondent} = session) do
    reallocate_respondent(session, respondent, ivr?(session), Session.current_timeout(session))
  end
end
