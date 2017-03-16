defmodule Ask.SurveyController do
  use Ask.Web, :api_controller

  alias Ask.{Project, Survey, Questionnaire}
  alias Ask.Runtime.Session

  def index(conn, %{"project_id" => project_id}) do
    surveys = conn
    |> load_project(project_id)
    |> assoc(:surveys)
    |> Repo.all

    render(conn, "index.json", surveys: surveys)
  end

  def create(conn, params = %{"project_id" => project_id}) do
    project = conn
    |> load_project_for_change(project_id)

    props = %{"project_id" => project_id,
              "name" => "",
              "schedule_start_time" => Ecto.Time.cast!("09:00:00"),
              "schedule_end_time" => Ecto.Time.cast!("18:00:00"),
              "timezone" => "UTC"}
    survey_params = Map.get(params, "survey", %{})
    props = Map.merge(props, survey_params)

    changeset = project
    |> build_assoc(:surveys)
    |> Survey.changeset(props)

    case Repo.insert(changeset) do
      {:ok, survey} ->
        project |> Project.touch!
        conn
        |> put_status(:created)
        |> put_resp_header("location", project_survey_path(conn, :show, project_id, survey))
        |> render("show.json", survey: survey |> Repo.preload([:quota_buckets]))
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(Ask.ChangesetView, "error.json", changeset: changeset)
    end
  end

  def show(conn, %{"project_id" => project_id, "id" => id}) do
    survey = conn
    |> load_project(project_id)
    |> assoc(:surveys)
    |> Repo.get!(id)
    |> Repo.preload([:quota_buckets])
    |> with_respondents_count

    render(conn, "show.json", survey: survey)
  end

  def update(conn, %{"project_id" => project_id, "id" => id, "survey" => survey_params}) do
    project = conn
    |> load_project_for_change(project_id)

    changeset = project
    |> assoc(:surveys)
    |> Repo.get!(id)
    |> Repo.preload([:questionnaires])
    |> Repo.preload([:quota_buckets])
    |> with_respondents_count
    |> Repo.preload(respondent_groups: :channels)
    |> Survey.changeset(survey_params)
    |> update_questionnaires(survey_params)
    |> Survey.update_state

    case Repo.update(changeset) do
      {:ok, survey} ->
        project |> Project.touch!
        render(conn, "show.json", survey: survey)
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(Ask.ChangesetView, "error.json", changeset: changeset)
    end
  end

  defp update_questionnaires(changeset, %{"questionnaire_ids" => questionnaires_params}) do
    questionnaires_changeset = Enum.map(questionnaires_params, fn ch ->
      Repo.get!(Questionnaire, ch) |> change
    end)

    changeset
    |> put_assoc(:questionnaires, questionnaires_changeset)
  end

  defp update_questionnaires(changeset, _) do
    changeset
  end

  defp with_respondents_count(survey) do
    respondents_count = survey |> assoc(:respondents) |> select(count("*")) |> Repo.one
    %{survey | respondents_count: respondents_count}
  end

  def delete(conn, %{"project_id" => project_id, "id" => id}) do
    project = conn
    |> load_project_for_change(project_id)

    survey = project
    |> assoc(:surveys)
    |> Repo.get!(id)

    case survey.state do
      "running" ->
        send_resp(conn, :bad_request, "")

      _ ->
        survey
        |> Repo.delete!

        project |> Project.touch!

        send_resp(conn, :no_content, "")
    end
  end

  def launch(conn, %{"survey_id" => id}) do
    survey = Repo.get!(Survey, id)
    |> Repo.preload([:quota_buckets])
    |> Repo.preload(respondent_groups: :channels)

    if survey.state != "ready" do
      conn
        |> put_status(:unprocessable_entity)
        |> render("show.json", survey: survey)
    else
      project = conn
      |> load_project_for_change(survey.project_id)

      channels = survey.respondent_groups
      |> Enum.flat_map(&(&1.channels))
      |> Enum.uniq

      case prepare_channels(conn, channels) do
        :ok ->
          changeset = Survey.changeset(survey, %{"state": "running", "started_at": Timex.now})
          case Repo.update(changeset) do
            {:ok, survey} ->
              project |> Project.touch!
              render(conn, "show.json", survey: survey)
            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> render(Ask.ChangesetView, "error.json", changeset: changeset)
          end

        {:error, _reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> render("show.json", survey: survey)
      end
    end
  end

  def stop(conn, %{"survey_id" => id}) do
    survey = Repo.get!(Survey, id)
    |> Repo.preload([:quota_buckets])

    case survey.state do
      "cancelled" ->
        # Cancelling a cancelled survey is idempotent.
        # We must not error, because this can happen if a user has the survey
        # UI open with the cancel button, and meanwhile the survey is cancelled
        # from another tab.
        conn
          |> render("show.json", survey: survey)
      "completed" ->
        # Cancelling a completed survey should have no effect.
        # We must not error, because this can happen if a user has the survey
        # UI open with the cancel button, and meanwhile the survey finished
        conn
          |> render("show.json", survey: survey)
      "running" ->
        project = conn
          |> load_project_for_change(survey.project_id)

        cancel_messages(survey)

        from(r in Ask.Respondent, where: (((r.state == "active") or (r.state == "stalled")) and (r.survey_id == ^survey.id)))
        |> Repo.update_all(set: [state: "cancelled", session: nil, timeout_at: nil])

        changeset = Survey.changeset(survey, %{"state": "cancelled"})
        case Repo.update(changeset) do
          {:ok, survey} ->
            project |> Project.touch!
            render(conn, "show.json", survey: survey)
          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> render(Ask.ChangesetView, "error.json", changeset: changeset)
        end
      _ ->
        # Cancelling a pending survey or a survey in any other state should
        # result in an error.
        conn
          |> put_status(:unprocessable_entity)
          |> render("show.json", survey: survey)
      end
  end

  defp prepare_channels(_, []), do: :ok
  defp prepare_channels(conn, [channel | rest]) do
    runtime_channel = Ask.Channel.runtime_channel(channel)
    case Ask.Runtime.Channel.prepare(runtime_channel, callback_url(conn, :callback, channel.provider)) do
      {:ok, _} -> prepare_channels(conn, rest)
      error -> error
    end
  end

  defp cancel_messages(survey) do
    # Need to save sessions in memory because they are set to nil
    # by the stop function above
    sessions = (from r in Ask.Respondent,
      where: r.survey_id == ^survey.id and not is_nil(r.session))
    |> Repo.all
    |> Enum.map(&(&1.session))

    spawn(fn ->
      sessions |> Enum.each(fn session ->
        session
        |> Session.load
        |> Session.cancel
      end)
    end)
  end
end
