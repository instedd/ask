defmodule Ask.Repo.Migrations.AddLastWindowEndsAtToSurveys do
  use Ecto.Migration

  def change do
    alter table(:surveys) do
      add :last_window_ends_at, :naive_datetime
    end
  end
end
