defmodule Ask.Project do
  use Ask.Web, :model

  schema "projects" do
    field :name, :string
    field :salt, :string
    field :colour_scheme, :string
    field :archived, :boolean, default: false

    has_many :questionnaires, Ask.Questionnaire
    has_many :surveys, Ask.Survey
    has_many :folders, Ask.Folder
    many_to_many :users, Ask.User, join_through: Ask.ProjectMembership, on_replace: :delete
    has_many :project_memberships, Ask.ProjectMembership
    many_to_many :channels, Ask.Channel, join_through: Ask.ProjectChannel, on_replace: :delete
    has_many :project_channels, Ask.ProjectChannel
    has_many :activity_logs, Ask.ActivityLog

    timestamps()
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:name, :salt, :colour_scheme, :archived])
    |> validate_colour_scheme
  end

  def touch!(project) do
    project
    |> Ask.Project.changeset
    |> Ask.Repo.update!(force: true)
  end

  defp validate_colour_scheme(changeset) do
    colour_scheme = get_field(changeset, :colour_scheme)
    cond do
      colour_scheme && !Enum.member?(["default", "better_data_for_health"], colour_scheme) ->
        add_error(changeset, :colour_scheme, "value has to be either default or better_data_for_health")
      true ->
        changeset
    end
  end
end
