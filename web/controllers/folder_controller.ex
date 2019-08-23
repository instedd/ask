defmodule Ask.FolderController do
  use Ask.Web, :api_controller

  alias Ask.{Folder, Logger, ActivityLog, Project}
  alias Ecto.Multi

  def create(conn, params = %{"project_id" => project_id}) do
    project = conn
    |> load_project_for_change(project_id)

    folder_params = Map.get(params, "folder", %{})
                      |> Map.put("project_id", project_id)

    %Folder{}
    |> Folder.changeset(folder_params)
    |> Repo.insert()
    |> case do
      {:ok, folder} ->
        project |> Project.touch!
        conn
        |> put_status(:created)
        |> render("show.json", folder: folder)

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(Ask.ChangesetView, "error.json", changeset: changeset)
    end
  end

  def index(conn, %{"project_id" => project_id}) do
    folders = (from f in Folder,
          where: f.project_id == ^project_id)
    |> Repo.all

    conn
    |> render("index.json", folders: folders)
  end

  def delete(conn, %{"project_id" => project_id, "id" => folder_id}) do
    conn
    |> load_project_for_change(project_id)

    folder = (from f in Folder,
      where: f.id == ^folder_id)
    |> Repo.one
    |> Repo.preload(:surveys)

    result = folder |> Folder.delete_changeset |> Repo.delete

    case result do
      {:ok, _} ->
        send_resp(conn, :no_content, "")
      {:error, changeset} ->
        Logger.warn "Error when deleting folder #{folder.id}"
        conn
        |> put_status(:unprocessable_entity)
        |> render(Ask.ChangesetView, "error.json", changeset: changeset)
    end
  end

  def set_name(conn, %{"project_id" => project_id, "folder_id" => folder_id, "name" => name}) do
    project =
      conn
      |> load_project_for_change(project_id)

    folder =
      project
      |> assoc(:folders)
      |> Repo.get!(folder_id)

    result =
      Multi.new()
      |> Multi.update(:set_name, Folder.changeset(folder, %{name: name}))
      |> Multi.insert(:rename_log, ActivityLog.rename_folder(project, conn, folder, folder.name, name))
      |> Repo.transaction()

    case result do
      {:ok, _} ->
        send_resp(conn, :no_content, "")

      {:error, _, changeset, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(Ask.ChangesetView, "error.json", changeset: changeset)
    end
  end

end
