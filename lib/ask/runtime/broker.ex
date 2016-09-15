defmodule Ask.Runtime.Broker do
  use GenServer
  import Ecto.Query
  import Ecto
  alias Ask.{Repo, Survey, Respondent}
  alias Ask.Runtime.Session

  @batch_size 10

  def init(_args) do
    :timer.send_interval(1000, :poll)
    {:ok, nil}
  end

  def handle_info(:poll, state) do
    surveys = Repo.all(from s in Survey, where: s.state == "running")
    surveys |> Enum.each(&poll_survey(&1))
    {:noreply, state}
  end

  defp poll_survey(survey) do
    by_state = Repo.all(
      from r in assoc(survey, :respondents),
      group_by: :state,
      select: {r.state, count("*")}) |> Enum.into(%{})

    active = by_state["active"] || 0
    pending = by_state["pending"] || 0

    cond do
      active == 0 && pending == 0 ->
        Repo.update Survey.changeset(survey, %{state: "completed"})

      active < @batch_size && pending > 0 ->
        enqueue_some(survey, @batch_size - active)

      true -> :ok
    end
  end

  defp enqueue_some(survey, count) do
    respondents = Repo.all(
      from r in assoc(survey, :respondents),
      where: r.state == "pending",
      limit: ^count)

    respondents |> Enum.each(&enqueue(survey, &1))
  end

  defp enqueue(survey, respondent) do
    Repo.update Respondent.changeset(respondent, %{state: "active"})

    survey = Repo.preload(survey, [:questionnaire, :channels])
    channel = hd(survey.channels)

    channel_config = Application.get_env(:ask, :channel)
    channel_provider = channel_config[:providers][channel.provider]

    runtime_channel = channel_provider.new(channel.settings)
    Session.start(survey.questionnaire, respondent.phone_number, runtime_channel)
  end
end
