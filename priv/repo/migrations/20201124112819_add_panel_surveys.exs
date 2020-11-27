defmodule Ask.Repo.Migrations.AddPanelSurveys do
  use Ecto.Migration

  def change do
    alter table(:surveys) do
      add :panel_survey_of, references(:surveys, on_delete: :nothing)
      add :latest_panel_survey, :boolean, default: false
    end
  end
end
