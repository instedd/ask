defmodule Ask.Repo.Migrations.CreateRetryStats do
  use Ecto.Migration

  def change do
    create table(:retry_stats) do
      add :mode, :string
      add :attempt, :integer
      add :retry_time, :string
      add :count, :integer
      add :survey_id, references(:surveys, on_delete: :delete_all)

      timestamps()
    end

    create unique_index(:retry_stats, [:mode, :attempt, :retry_time, :survey_id])
  end
end
