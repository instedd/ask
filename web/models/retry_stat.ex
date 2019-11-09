defmodule Ask.RetryStat do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias Ask.{RetryStat, Repo}
  alias Ask.Ecto.Type.JSON

  schema "retry_stats" do
    field(:attempt, :integer)
    field(:count, :integer)
    field(:mode, JSON)
    field(:retry_time, :string)
    belongs_to(:survey, Ask.Survey)

    timestamps()
  end

  def changeset(%RetryStat{} = retry_stat, attrs) do
    retry_stat
    |> cast(attrs, [:mode, :attempt, :retry_time, :count, :survey_id])
    |> validate_required([:mode, :attempt, :retry_time, :count, :survey_id])
    |> unique_constraint(:retry_stats_mode_attempt_retry_time_survey_id_index)
  end

  def add!(%{attempt: attempt, mode: mode, retry_time: retry_time, survey_id: survey_id}) do
    {:ok, updated} =
      Repo.insert(
        %RetryStat{
          attempt: attempt,
          count: 1,
          mode: mode,
          retry_time: retry_time,
          survey_id: survey_id
        },
        returning: [:amount],
        on_conflict: [inc: [count: 1]]
      )

    {:ok, updated}
  end

  def subtract!(filter) do
    case get(filter) do
      nil ->
        {:error, :not_found}

      stat ->
        subtract_stat(stat)
    end
  end

  defp subtract_stat(stat) do
    case from(s in RetryStat, where: s.id == ^stat.id and s.count > 0, update: [inc: [count: -1]])
         |> Repo.update_all([]) do
      {0, _} ->
        {:error, :zero_reached}

      {_, _} ->
        {:ok, stat}
    end
  end

  def stats(%{survey_id: survey_id}), do:
    Repo.all(
           from(
             rs in RetryStat,
             where:
              rs.count > 0 and rs.survey_id == ^survey_id
           )
         )

  def count(stats, %{overdue: true} = filter), do: stats |> count_overdue(filter)

  def count(stats, %{attempt: filter_attempt, mode: filter_mode, retry_time: filter_retry_time}),
    do:
      Enum.find(stats, fn %RetryStat{attempt: attempt, retry_time: retry_time, mode: mode} -> attempt == filter_attempt and retry_time == filter_retry_time and mode == filter_mode end) |> count_stat

  defp count_overdue(stats, %{attempt: filter_attempt, mode: filter_mode, retry_time: filter_retry_time}),
    do:
      stats
      |> Enum.filter(fn %RetryStat{attempt: attempt, retry_time: retry_time, mode: mode} -> attempt == filter_attempt and retry_time != "" and retry_time <= filter_retry_time and mode == filter_mode end)
      |> Enum.map(fn stat -> stat |> count_stat() end)
      |> Enum.sum()

  defp count_stat(nil), do: 0
  defp count_stat(stat), do: stat.count

  defp get(%{attempt: attempt, mode: mode, retry_time: retry_time, survey_id: survey_id}),
    do:
      RetryStat
      |> Repo.get_by(attempt: attempt, mode: mode, retry_time: retry_time, survey_id: survey_id)

  def retry_time(timeout_at), do: Timex.format!(timeout_at, "%Y%0m%0d%H", :strftime)
end
