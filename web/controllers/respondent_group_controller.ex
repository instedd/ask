defmodule Ask.RespondentGroupController do
  use Ask.Web, :api_controller
  alias Ask.{Project, Survey, Respondent, RespondentGroup, Logger, RespondentGroupChannel}

  plug :find_and_check_survey_state when action in [:create, :update, :delete, :replace]

  def index(conn, %{"project_id" => project_id, "survey_id" => survey_id}) do
    project = conn
    |> load_project(project_id)

    respondent_groups = project
    |> assoc(:surveys)
    |> Repo.get!(survey_id)
    |> assoc(:respondent_groups)
    |> preload(respondent_group_channels: :channel)
    |> Repo.all

    render(conn, "index.json", respondent_groups: respondent_groups)
  end

  def create(conn, %{"file" => file}) do
    project = conn.assigns.loaded_project
    survey = conn.assigns.loaded_survey

    process_file(conn, survey, file, fn rows ->
      create_respondent_group(conn, survey, file.filename, rows, project)
    end)
  end

  def update(conn, %{"id" => id, "respondent_group" => respondent_group_params}) do
    project = conn.assigns.loaded_project
    survey = conn.assigns.loaded_survey

    group = survey
    |> assoc(:respondent_groups)
    |> Repo.get!(id)
    |> RespondentGroup.changeset(respondent_group_params)
    |> Repo.update!

    update_channels(id, respondent_group_params)

    group = group
    |> Repo.preload(:respondent_group_channels)

    survey
    |> Repo.preload([:questionnaires])
    |> Repo.preload([:quota_buckets])
    |> Repo.preload(respondent_groups: [respondent_group_channels: :channel])
    |> change
    |> Survey.update_state
    |> Repo.update!

    project |> Project.touch!

    conn
    |> render("show.json", respondent_group: group)
  end

  def add(conn, %{"project_id" => project_id, "survey_id" => survey_id, "respondent_group_id" => id, "file" => file}) do
    project = conn
    |> load_project_for_change(project_id)

    survey = project
    |> assoc(:surveys)
    |> Repo.get!(survey_id)

    group = survey
    |> assoc(:respondent_groups)
    |> Repo.get!(id)
    |> Repo.preload(:respondent_group_channels)

    project |> Project.touch!

    case survey.locked do
      false ->
        process_file(conn, survey, file, fn rows ->
          {:ok, local_time } = Ecto.DateTime.cast :calendar.local_time()

          rows = rows
          |> remove_duplicates_with_respect_to(group)

          Ask.Runtime.RespondentGroup.insert_all_respondents(rows, project, survey, group, local_time)

          new_count = group.respondents_count + length(rows)
          new_sample = merge_sample(group.sample, rows)

          group = group
          |> RespondentGroup.changeset(%{"respondents_count" => new_count, "sample" => new_sample})
          |> Repo.update!

          conn
          |> render("show.json", respondent_group: group)
        end)
      true ->
        conn
        |> put_status(:unprocessable_entity)
        |> render("show.json", respondent_group: group)
      end
  end

  def replace(conn, %{"respondent_group_id" => id, "file" => file}) do
    project = conn.assigns.loaded_project
    survey = conn.assigns.loaded_survey

    group = survey
    |> assoc(:respondent_groups)
    |> Repo.get!(id)

    process_file(conn, survey, file, fn rows ->
      {:ok, local_time } = Ecto.DateTime.cast :calendar.local_time()

      # First delete existing respondents from that group
      Repo.delete_all(from r in Respondent,
        where: r.respondent_group_id == ^group.id)

      # Then create respondents from the CSV file
      Ask.Runtime.RespondentGroup.insert_all_respondents(rows, project, survey, group, local_time)

      sample = rows |> Enum.take(5)
      respondents_count = rows |> length

      group = group
      |> RespondentGroup.changeset(%{
        "sample" => sample,
        "respondents_count" => respondents_count,
      })
      |> Repo.update!
      |> Repo.preload(:respondent_group_channels)

      project |> Project.touch!

      conn
      |> render("show.json", respondent_group: group)
    end)
  end

  defp update_channels(id, %{"channels" => channels_params}) do
    from(gch in RespondentGroupChannel, where: gch.respondent_group_id == ^id) |> Repo.delete_all

    Repo.transaction fn ->
      Enum.each(channels_params, fn ch ->
        RespondentGroupChannel.changeset(%RespondentGroupChannel{}, %{respondent_group_id: id, channel_id: ch["id"], mode: ch["mode"]})
        |> Repo.insert
      end)
    end
  end

  defp update_channels(_, _), do: nil

  defp csv_rows(csv_string) do
    csv_string
    |> String.splitter(["\r\n", "\r", "\n"])
    |> Stream.map(fn r -> r |> String.split(",") |> Enum.at(0) |> String.trim end)
    |> Stream.filter(fn r -> String.length(r) != 0 end)
  end

  defp create_respondent_group(conn, survey, filename, rows, project) do
    {:ok, local_time } = Ecto.DateTime.cast :calendar.local_time()

    sample = rows |> Enum.take(5)
    respondents_count = rows |> length

    group = %RespondentGroup{
      name: filename,
      survey_id: survey.id,
      sample: sample,
      respondents_count: respondents_count
    }
    |> Repo.insert!
    |> Repo.preload(:respondent_group_channels)

    Ask.Runtime.RespondentGroup.insert_all_respondents(rows, project, survey, group, local_time)

    survey
    |> Repo.preload([:questionnaires])
    |> Repo.preload([:quota_buckets])
    |> Repo.preload(respondent_groups: [respondent_group_channels: :channel])
    |> change
    |> Survey.update_state
    |> Repo.update!

    project |> Project.touch!

    conn
    |> put_status(:created)
    |> render("show.json", respondent_group: group)
  end

  defp render_unprocessable_entity(conn) do
    conn
    |> put_status(:unprocessable_entity)
    |> render(Ask.ChangesetView, "error.json", changeset: change(%Respondent{}, %{}))
  end

  defp render_invalid(conn, filename, invalid_entries) do
    conn
    |> put_status(:unprocessable_entity)
    |> render("invalid_entries.json", %{invalid_entries: invalid_entries, filename: filename})
  end

  def delete(conn, %{"id" => id}) do
    project = conn.assigns.loaded_project
    survey = conn.assigns.loaded_survey

    # Check that the respondent_group is in the survey
    group = survey
    |> assoc(:respondent_groups)
    |> Repo.get!(id)

    from(r in Respondent, where: r.respondent_group_id == ^id)
    |> Repo.delete_all

    group
    |> Repo.delete!

    survey
    |> Repo.preload([:questionnaires])
    |> Repo.preload([:quota_buckets])
    |> Repo.preload(respondent_groups: [respondent_group_channels: :channel])
    |> change
    |> Survey.update_state
    |> Repo.update!

    project |> Project.touch!
    conn
      |> put_status(:ok)
      |> render("empty.json", %{})
  end

  defp process_file(conn, survey, file, func) do
    if Path.extname(file.filename) == ".csv" do
      rows =
        file.path
        |> File.read!
        |> Ask.BomParser.parse
        |> csv_rows
        |> Enum.uniq_by(&keep_digits/1)

      if length(rows) == 0 do
        render_invalid(conn, file.filename, [])
      else
        invalid_entries = rows
          |> Stream.with_index
          |> Stream.filter(fn {row, _} -> !Regex.match?(~r/^([0-9]|\(|\)|\+|\-| )+$/, row) end)
          |> Stream.map(fn {row, index} -> %{phone_number: row, line_number: index + 1} end)
          |> Enum.to_list

        case invalid_entries do
          [] -> func.(rows)
          _ -> render_invalid(conn, file.filename, invalid_entries)
        end
      end
    else
      Logger.warn "Error when creating respondent group for survey: #{inspect survey}"
      render_unprocessable_entity(conn)
    end
  end

  defp merge_sample(old_sample, new_rows) do
    if length(old_sample) == 5 do
      old_sample
    else
      old_sample ++ Enum.take(new_rows, 5 - length(old_sample))
    end
  end

  defp remove_duplicates_with_respect_to(phone_numbers, group) do
    # Select numbers that already exist in the DB
    canonical_numbers = Enum.map(phone_numbers, &Respondent.canonicalize_phone_number/1)
    existing_numbers = Repo.all(from r in Respondent,
      where: r.respondent_group_id == ^group.id,
      where: r.canonical_phone_number in ^canonical_numbers,
      select: r.canonical_phone_number)

    # And then remove them from phone_numbers (because they are duplicates)
    # (no easier way to do this, plus we expect `existing_numbers` to
    # be empty or near empty)
    Enum.reject(phone_numbers, fn num ->
      Respondent.canonicalize_phone_number(num) in existing_numbers
    end)
  end

  defp keep_digits(string) do
    Regex.replace(~r/\D/, string, "", [:global])
  end

  defp find_and_check_survey_state(conn, _options) do
    %{"project_id" => project_id, "survey_id" => survey_id} = conn.params

    project = conn
    |> load_project_for_change(project_id)

    survey = project
    |> assoc(:surveys)
    |> Repo.get!(survey_id)

    if survey |> Survey.editable? do
        assign(conn, :loaded_survey, survey)
          |> assign(:loaded_project, project)
    else
      conn
        |> render_unprocessable_entity
        |> halt()
    end
  end
end
