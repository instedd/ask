defmodule Ask.Repo.Migrations.FillLastWindowEndsAtInSurveys do
  use Ecto.Migration

  def up do
    Ask.Repo.query("UPDATE surveys SET last_window_ends_at = ended_at WHERE ended_at IS NOT NULL")
  end

  def down do
    Ask.Repo.query("UPDATE surveys SET last_window_ends_at = null WHERE last_window_ends_at IS NOT NULL")
  end
end
