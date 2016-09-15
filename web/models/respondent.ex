defmodule Ask.Respondent do
  use Ask.Web, :model

  schema "respondents" do
    field :phone_number, :string
    field :state, :string, default: "pending" # [pending, active, completed, failed]
    belongs_to :survey, Ask.Survey

    timestamps()
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:phone_number, :state])
    |> validate_required([:phone_number, :state])
  end
end
