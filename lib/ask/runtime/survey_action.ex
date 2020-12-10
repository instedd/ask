defmodule Ask.Runtime.SurveyAction do
  alias Ask.{Survey, Logger, Repo, Questionnaire}
  alias Ask.Runtime.PanelSurvey
  alias Ecto.Multi

  def start(survey, options \\ []) do
    survey =
      survey
      |> Repo.preload([:project])
      |> Repo.preload([:quota_buckets])
      |> Repo.preload([:questionnaires])
      |> Repo.preload(respondent_groups: :channels)

    if survey.state == "ready" do
      channels =
        survey.respondent_groups
        |> Enum.flat_map(& &1.channels)
        |> Enum.uniq()

      case prepare_channels(channels) do
        :ok ->
          repetition? = Keyword.get(options, :repetition?, false)
          perform_start(survey, repetition?)

        {:error, reason} ->
          Logger.warn(
            "Error when preparing channels for launching survey #{survey.id} (#{reason})"
          )

          {:error, %{survey: survey}}
      end
    else
      Logger.warn("Error when launching survey #{survey.id}. State is not ready ")
      {:error, %{survey: survey}}
    end
  end

  def repeat(survey) do
    if Survey.succeeded?(survey) and Survey.panel_survey?(survey) do
      case create_panel_survey_occurrence(survey) do
        {:ok, %{survey: new_occurrence}} ->
          start(new_occurrence, repetition?: true)

        result ->
          result
      end
    else
      Logger.warn(
        "Survey #{survey.id} can't be repeated because it's not a panel survey or it didn's succeeded"
      )

      {:error, %{survey: survey}}
    end
  end

  defp perform_start(survey, repetition?) do
    changeset = Survey.changeset(survey, %{state: "running", started_at: Timex.now()})

    case Repo.update(changeset) do
      {:ok, _} ->
        survey = if repetition?, do: survey, else: create_survey_questionnaires_snapshot(survey)

        {:ok, %{survey: survey}}

      {:error, _, changeset, _} ->
        Logger.warn("Error when launching survey: #{inspect(changeset)}")
        {:error, %{changeset: changeset}}
    end
  end

  defp prepare_channels([]), do: :ok

  defp prepare_channels([channel | rest]) do
    runtime_channel = Ask.Channel.runtime_channel(channel)

    case Ask.Runtime.Channel.prepare(runtime_channel) do
      {:ok, _} -> prepare_channels(rest)
      error -> error
    end
  end

  defp create_survey_questionnaires_snapshot(survey) do
    # Create copies of questionnaires
    new_questionnaires =
      Enum.map(survey.questionnaires, fn questionnaire ->
        %{
          questionnaire
          | id: nil,
            snapshot_of_questionnaire: questionnaire,
            questionnaire_variables: [],
            project: survey.project
        }
        |> Repo.preload(:translations)
        |> Repo.insert!()
        |> Questionnaire.recreate_variables!()
      end)

    # Update references in comparisons, if any
    comparisons = survey.comparisons

    comparisons =
      if comparisons do
        comparisons
        |> Enum.map(fn comparison ->
          questionnaire_id = Map.get(comparison, "questionnaire_id")
          snapshot = Enum.find(new_questionnaires, fn q -> q.snapshot_of == questionnaire_id end)
          Map.put(comparison, "questionnaire_id", snapshot.id)
        end)
      else
        comparisons
      end

    survey
    |> Survey.changeset(%{comparisons: comparisons})
    |> Ecto.Changeset.put_assoc(:questionnaires, new_questionnaires)
    |> Repo.update!()
  end

  defp create_panel_survey_occurrence(survey) do
    survey =
      survey
      |> Repo.preload([:project])
      |> Repo.preload([:questionnaires])

    update_changeset = Survey.changeset(survey, %{latest_panel_survey: false})

    multi =
      Multi.new()
      |> Multi.update(:update, update_changeset)
      |> Multi.insert(:insert, PanelSurvey.new_ocurrence_changeset(survey))
      |> Repo.transaction()

    case multi do
      {:ok, %{insert: survey}} ->
        {:ok, %{survey: survey}}

      {:error, _, changeset, _} ->
        {:error, %{changeset: changeset}}
    end
  end
end
