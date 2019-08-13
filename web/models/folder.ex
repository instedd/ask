defmodule Ask.Folder do
  use Ask.Web, :model
  alias Ask.{
    Project
  }

  schema "folders" do
    field :name, :string

    belongs_to :project, Project
    timestamps()
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:name, :project_id])
    |> validate_required([:name, :project_id])
    |> unique_constraint(:name, name: :folders_name_project_id_index)
  end
end
