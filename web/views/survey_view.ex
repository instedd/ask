defmodule Ask.SurveyView do
  import Ask.Router.Helpers
  alias Ask.Endpoint
  use Ask.Web, :view

  alias Ask.Survey

  def render("index.json", %{surveys: surveys}) do
    %{data: render_many(surveys, Ask.SurveyView, "survey.json")}
  end
  def render("show.json", %{survey: survey}) do
    %{data: render_one(survey, Ask.SurveyView, "survey_detail.json")}
  end
  def render("config.json", %{config: config}) do
    config
  end
  def render("stats.json", %{success_rate_data: success_rate_data, queue_size_data: queue_size_data}) do
    %{
      data:
      %{
        success_rate: success_rate_data.success_rate,
        completion_rate: success_rate_data.completion_rate,
        initial_success_rate: success_rate_data.initial_success_rate,
        estimated_success_rate: success_rate_data.estimated_success_rate,
        completes: queue_size_data.completes,
        missing: queue_size_data.missing,
        multiplier: queue_size_data.multiplier,
        needed: queue_size_data.needed,
        pending: queue_size_data.pending
      }
    }
  end
  def render("retries_histograms.json", %{histograms: histograms}) do
    %{
      data: histograms
    }
  end
  def render("survey.json", %{survey: survey}) do
    started_at = if (survey.started_at), do: survey.started_at |> Timex.format!("%FT%T%:z", :strftime), else: nil

    %{id: survey.id,
      name: survey.name,
      description: survey.description,
      mode: survey.mode,
      project_id: survey.project_id,
      state: survey.state,
      locked: survey.locked,
      exit_code: survey.exit_code,
      exit_message: survey.exit_message,
      cutoff: survey.cutoff,
      schedule: survey.schedule,
      started_at: started_at,
      next_schedule_time: next_schedule_time(survey),
      updated_at: survey.updated_at,
      down_channels: survey.down_channels,
      folder_id: survey.folder_id
    }
  end
  def render("survey_detail.json", %{survey: survey}) do
    started_at = if (survey.started_at), do: survey.started_at |> Timex.format!("%FT%T%:z", :strftime), else: nil

    map = %{id: survey.id,
      name: survey.name,
      description: survey.description,
      mode: survey.mode,
      project_id: survey.project_id,
      state: survey.state,
      locked: survey.locked,
      exit_code: survey.exit_code,
      exit_message: survey.exit_message,
      questionnaire_ids: questionnaire_ids(survey),
      cutoff: survey.cutoff,
      count_partial_results: survey.count_partial_results,
      schedule: survey.schedule,
      started_at: started_at,
      updated_at: survey.updated_at,
      sms_retry_configuration: survey.sms_retry_configuration,
      ivr_retry_configuration: survey.ivr_retry_configuration,
      mobileweb_retry_configuration: survey.mobileweb_retry_configuration,
      fallback_delay: survey.fallback_delay,
      quotas: %{
        buckets: render_many(survey.quota_buckets, Ask.SurveyView, "survey_bucket.json", as: :bucket),
        vars: survey.quota_vars || []
      },
      links: render_many(survey.links, Ask.SurveyView, "link.json", as: :link),
      comparisons: survey.comparisons || [],
      next_schedule_time: next_schedule_time(survey),
      down_channels: survey.down_channels
    }

    if Ask.Survey.launched?(survey) || survey.simulation do
      qs = survey.questionnaires
      |> Enum.map(fn q ->
        {to_string(q.id), %{id: q.id, name: q.name, valid: true, modes: q.modes}}
      end)
      |> Enum.into(%{})
      Map.put(map, :questionnaires, qs)
    else
      map
    end
  end
  def render("survey_bucket.json", %{bucket: bucket}) do
    condition =
      bucket.condition
      |> Enum.reduce([], fn {store, value}, conditions ->
        [%{"store" => store, "value" => value} | conditions]
      end)
    %{
      "condition" => condition,
      "quota" => bucket.quota,
      "count" => bucket.count
    }
  end
  def render("link.json", %{link: link}) do
    %{
      "name" => link.name,
      "url" => short_link_url(Endpoint, :access, link.hash)
    }
  end

  defp questionnaire_ids(survey = %Ask.Survey{}) do
    (survey
    |> Ask.Repo.preload(:questionnaires)).questionnaires
    |> Enum.map(&(&1.id))
  end

  defp next_schedule_time(survey) do
    now = DateTime.utc_now
    next_schedule_time = Survey.next_available_date_time(survey, now)
    if next_schedule_time == now  do
      nil
    else
      next_schedule_time
      |> Timex.Timezone.convert(survey.schedule.timezone)
    end
  end
end
