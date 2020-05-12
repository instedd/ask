defmodule Ask.QuestionnaireView do
  use Ask.Web, :view

  def render("index.json", %{questionnaires: questionnaires}) do
    %{data: render_many(questionnaires, Ask.QuestionnaireView, "questionnaire.json")}
  end

  def render("show.json", %{questionnaire: questionnaire}) do
    %{data: render_one(questionnaire, Ask.QuestionnaireView, "questionnaire.json")}
  end

  def render("questionnaire.json", %{questionnaire: questionnaire}) do
    %{id: questionnaire.id,
      name: questionnaire.name,
      description: questionnaire.description,
      modes: questionnaire.modes,
      updated_at: questionnaire.updated_at,
      project_id: questionnaire.project_id,
      steps: questionnaire.steps,
      quota_completed_steps: questionnaire.quota_completed_steps,
      default_language: questionnaire.default_language,
      languages: questionnaire.languages,
      settings: questionnaire.settings,
      valid: questionnaire.valid,
      partial_relevant_config: questionnaire.partial_relevant_config,
    }
  end

  def render("simulation.json", %{simulation: simulation}) do
    %{
      respondent_id: simulation.respondent_id,
      simulation_status: simulation.simulation_status,
      disposition: simulation.disposition,
      messages_history: simulation.messages_history,
      submissions: simulation.submissions,
      current_step: simulation.current_step
    }
  end
end
