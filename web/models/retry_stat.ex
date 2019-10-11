defmodule Ask.RetryStat do
  use Ecto.Schema
  import Ecto.Changeset
  alias Ask.RetryStat

  schema "retry_stats" do
    field(:attempt, :integer)
    field(:count, :integer)
    field(:mode, :string)
    field(:retry_time, :string)
    belongs_to(:survey, Ask.Survey)

    timestamps()
  end

  @doc false
  def changeset(%RetryStat{} = retry_stat, attrs) do
    retry_stat
    |> cast(attrs, [:mode, :attempt, :retry_time, :count, :survey_id])
    |> validate_required([:mode, :attempt, :retry_time, :count, :survey_id])
    |> unique_constraint(:retry_stats_mode_attempt_retry_time_survey_id_index)
  end
end
