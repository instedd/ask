defmodule Ask.RespondentGroup do
  use Ask.Web, :model

  schema "respondent_groups" do
    field :name, :string
    # In Surveda informal talks, we use a lot the word "sample" to represent all the respondents
    # of a group or survey.
    # Here, the name "sample" is literal. In this field we keep only the very few first phone
    # numbers shown to the end-user as a sample in the UI.
    field :sample, Ask.Ecto.Type.JSON
    field :respondents_count, :integer
    belongs_to :survey, Ask.Survey
    has_many :respondents, Ask.Respondent
    has_many :respondent_group_channels, Ask.RespondentGroupChannel, on_delete: :delete_all
    many_to_many :channels, Ask.Channel, join_through: Ask.RespondentGroupChannel, on_replace: :delete

    timestamps()
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:name, :sample, :respondents_count])
    |> validate_required([:name, :sample, :respondents_count])
  end

  def primary_channel(respondent_group, modes) do
    case modes do
      [mode | _] -> channel(respondent_group, mode)
      _ -> nil
    end
  end

  def fallback_channel(respondent_group, modes) do
    case modes do
      [_, mode] -> channel(respondent_group, mode)
      _ -> nil
    end
  end

  defp channel(respondent_group, mode) do
    (respondent_group.respondent_group_channels |> Enum.find(fn c -> c.mode == mode end)).channel
  end
end
