defmodule Ask.Runtime.PanelSurvey do
  def new_ocurrence(survey) do
    %{
      # basic settings
      project_id: survey.project_id,
      folder_id: survey.folder_id,
      name: survey.name,
      description: survey.description,
      mode: survey.mode,
      state: "running",
      started_at: Timex.now,
      panel_survey_of: survey.panel_survey_of,
      latest_panel_survey: true,
      # advanced settings
      cutoff: survey.cutoff,
      count_partial_results: survey.count_partial_results,
      schedule: survey.schedule,
      sms_retry_configuration: survey.sms_retry_configuration,
      ivr_retry_configuration: survey.ivr_retry_configuration,
      mobileweb_retry_configuration: survey.mobileweb_retry_configuration,
      fallback_delay: survey.fallback_delay,
      quota_vars: survey.quota_vars,
      quotas: survey.quotas
    }
  end
end
