defmodule Ask.FloipPackage do
  import Ecto.Query
  alias Ask.{Repo, Survey, Response, Respondent}

  def created_at(survey) do
    survey.started_at
  end

  def modified_at(survey) do
    survey.started_at
  end

  def responses(survey) do
    stream = (from r in Response,
      join: respondent in Respondent,
      where: respondent.survey_id == ^survey.id and r.respondent_id == respondent.id,
      select: {r, respondent})
      |> Repo.stream
      |> Stream.map(fn {r, respondent} ->
        timestamp = DateTime.to_iso8601(r.inserted_at, :extended)
        [timestamp, r.id, respondent.hashed_number, r.field_name, r.value, %{}]
      end)

    {:ok, responses} = Repo.transaction(fn() -> Enum.to_list(stream) end)

    responses
  end

  def questions(survey) do
    survey = survey |> Repo.preload(:questionnaires)

    survey.questionnaires
    |> Enum.flat_map(fn(q) -> q.steps end)
    |> Enum.filter(&floip_question?/1)
    |> Enum.reduce(%{}, fn(step, acc) -> Map.put(acc, step["store"], to_floip_question(step)) end)
  end

  def to_floip_question(step = %{"type" => "multiple-choice"}) do
    choices = step["choices"]
    |> Enum.map(fn(choice) -> choice["value"] end)

    %{
      "type" => "select_one",
      "label" => step["title"],
      "type_options" => %{
        "choices" => choices
      }
    }
  end

  def to_floip_question(step = %{"type" => "numeric"}) do
    %{
      "type" => "numeric",
      "label" => step["title"],
      "type_options" => %{}
    }
  end

  def floip_question?(step) do
    ["multiple-choice", "numeric"]
    |> Enum.member?(step["type"])
  end

  def fields() do
    [
      %{
        "name" => "timestamp",
        "title" => "Timestamp",
        "type" => "datetime"
      },
      %{
        "name" => "row_id",
        "title" => "Row ID",
        "type" => "string"
      },
      %{
        "name" => "contact_id",
        "title" => "Contact ID",
        "type" => "string"
      },
      %{
        "name" => "question_id",
        "title" => "Question ID",
        "type" => "string"
      },
      %{
        "name" => "response_id",
        "title" => "Response ID",
        "type" => "any"
      },
      %{
        "name" => "response_metadata",
        "title" => "Response Metadata",
        "type" => "object"
      }
    ]
  end
end