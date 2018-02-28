defmodule Ask.RespondentView do
  use Ask.Web, :view

  def render("index.json", %{respondents: respondents, respondents_count: respondents_count}) do
    %{data: %{respondents: render_many(respondents, Ask.RespondentView, "respondent.json")}, meta: %{count: respondents_count}}
  end

  def render("show.json", %{respondent: respondent}) do
    %{data: render_one(respondent, Ask.RespondentView, "respondent.json")}
  end

  def render("empty.json", %{respondent: _respondent}) do
    %{data: %{}}
  end

  def render("respondent.json", %{respondent: respondent}) do
    date = case respondent.responses do
      [] -> nil
      _ -> respondent.responses |>  Enum.map(fn r -> r.updated_at end) |> Enum.max
    end
    responses = render_many(respondent.responses, Ask.RespondentView, "response.json", as: :response)

    if respondent.experiment_name do
      %{
        id: respondent.id,
        phone_number: respondent.hashed_number,
        survey_id: respondent.survey_id,
        mode: respondent.mode,
        effective_modes: respondent.effective_modes,
        questionnaire_id: respondent.questionnaire_id,
        responses: responses,
        disposition: respondent.disposition,
        date: date,
        updated_at: respondent.updated_at,
        experiment_name: respondent.experiment_name
      }
    else
      %{
        id: respondent.id,
        phone_number: respondent.hashed_number,
        survey_id: respondent.survey_id,
        effective_modes: respondent.effective_modes,
        mode: respondent.mode,
        questionnaire_id: respondent.questionnaire_id,
        responses: responses,
        disposition: respondent.disposition,
        date: date,
        updated_at: respondent.updated_at
      }
    end
  end

  def render("response.json", %{response: response}) do
    %{
      name: response.field_name,
      value: response.value
    }
  end

  def render("stats.json", %{stats: %{id: id, respondents_by_disposition: respondents_by_disposition, reference: reference, cumulative_percentages: cumulative_percentages, contacted_respondents: contacted_respondents, total_respondents: total_respondents, target: target, completion_percentage: completion_percentage}}) do
    %{
      data: %{
        id: id,
        reference: reference,
        respondents_by_disposition: respondents_by_disposition,
        cumulative_percentages:
          cumulative_percentages
          |> Enum.map(fn {questionnaire_id, date_percentages} ->
            {to_string(questionnaire_id), render_many(date_percentages, Ask.RespondentView, "date_percentages.json", as: :completed)}
          end)
          |> Enum.into(%{}),
        completion_percentage: completion_percentage,
        contacted_respondents: contacted_respondents,
        total_respondents: total_respondents,
        target: target
      }
    }
  end

  def render("quotas_stats.json", %{stats: %{id: id, reference: buckets, respondents_by_disposition: respondents_by_disposition, cumulative_percentages: cumulative_percentages, contacted_respondents: contacted_respondents, total_respondents: total_respondents, target: target, completion_percentage: completion_percentage}}) do
    %{
      data: %{
        id: id,
        respondents_by_disposition: respondents_by_disposition,
        reference: render_many(buckets, Ask.RespondentView, "survey_bucket.json", as: :bucket),
        cumulative_percentages:
          cumulative_percentages
          |> Enum.map(fn {questionnaire_id, date_percentages} ->
            {to_string(questionnaire_id), render_many(date_percentages, Ask.RespondentView, "date_percentages.json", as: :completed)}
          end)
          |> Enum.into(%{}),
        completion_percentage: completion_percentage,
        contacted_respondents: contacted_respondents,
        total_respondents: total_respondents,
        target: target
      }
    }
  end

  def render("survey_bucket.json", %{bucket: bucket}) do
    condition =
      bucket.condition
      |> Enum.reduce([], fn {store, value}, conditions ->
        value = case value do
          [lower, upper] -> "#{lower} - #{upper}"
          _ -> value
        end
        ["#{store}: #{value}" | conditions]
      end)
      |> Enum.join(" - ")
    %{
      "id" => bucket.id,
      "name" => condition
    }
  end

  def render("date_percentages.json", %{completed: {date, percentage}}) do
    %{
      date: Ecto.Date.cast!(date) |> Ecto.Date.to_string,
      percent: percentage
    }
  end
end
