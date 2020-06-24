defmodule Ask.RespondentView do
  use Ask.Web, :view

  def render(
        "index.json",
        %{
          index_fields: index_fields
        } = args
      ) do
    render_index(args)
    |> render_index_with_fields(index_fields)
  end

  def render("index.json", args), do: render_index(args)

  def render("index_field.json", %{respondent: "phoneNumber"}) do
    %{
      displayText: Ask.Gettext.gettext("Respondent ID"),
      key: "phoneNumber",
      sortable: true,
      type: "text"
    }
  end

  def render("index_field.json", %{respondent: "disposition"}) do
    %{
      displayText: Ask.Gettext.gettext("Disposition"),
      key: "disposition",
      sortable: false,
      type: "text"
    }
  end

  def render("index_field.json", %{respondent: "updated_at"}) do
    %{
      displayText: Ask.Gettext.gettext("Date"),
      key: "date",
      sortable: true,
      type: "date"
    }
  end

  def render("index_field.json", %{respondent: key}) do
    %{
      displayText: key,
      key: key,
      sortable: false
    }
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
        stats: respondent.stats,
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
        stats: respondent.stats,
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

  def render("stats.json", %{stats: nil}) do
    %{
      data: %{
        reference: %{},
        respondents_by_disposition: %{},
        cumulative_percentages: %{},
        completion_percentage: 0,
        attempted_respondents: 0,
        total_respondents: 0,
        target: 0
      }
    }
  end

  def render("stats.json", %{stats: %{id: id, respondents_by_disposition: respondents_by_disposition, reference: reference, cumulative_percentages: cumulative_percentages, attempted_respondents: attempted_respondents, total_respondents: total_respondents, target: target, completion_percentage: completion_percentage}}) do
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
        attempted_respondents: attempted_respondents,
        total_respondents: total_respondents,
        target: target
      }
    }
  end

  def render("quotas_stats.json", %{stats: %{id: id, reference: buckets, respondents_by_disposition: respondents_by_disposition, cumulative_percentages: cumulative_percentages, attempted_respondents: attempted_respondents, total_respondents: total_respondents, target: target, completion_percentage: completion_percentage}}) do
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
        attempted_respondents: attempted_respondents,
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
      date: Date.to_iso8601(date),
      percent: percentage
    }
  end

  defp render_index(%{
         respondents: respondents,
         respondents_count: respondents_count
       }) do
    %{
      data: %{respondents: render_many(respondents, Ask.RespondentView, "respondent.json")},
      meta: %{
        count: respondents_count
      }
    }
  end

  defp render_index_with_fields(render, fields) do
    meta_with_fields =
      Map.put(
        render[:meta],
        :fields,
        render_many(fields, Ask.RespondentView, "index_field.json")
      )
    Map.put(render, :meta, meta_with_fields)
  end
end
