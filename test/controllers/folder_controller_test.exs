defmodule Ask.FolderControllerTest do
  use Ask.ConnCase
  use Ask.DummySteps
  use Ask.TestHelpers

  alias Ask.{Folder}
  @valid_attrs %{name: "some content"}

  setup %{conn: conn} do
    user = insert(:user)
    conn = conn
      |> put_private(:test_user, user)
      |> put_req_header("accept", "application/json")
    {:ok, conn: conn, user: user}
  end

  describe "show" do

    test "shows chosen resource", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      folder = insert(:folder, project: project)
      folder = Folder |> Repo.get(folder.id)
      conn = get conn, project_folder_path(conn, :show, project, folder)
      assert json_response(conn, 200)["data"] == %{
        "id" => folder.id,
        "name" => folder.name,
        "project_id" => folder.project_id
      }
    end

    test "returns 404 when the project does not exist", %{conn: conn} do
      folder = insert(:folder)
      assert_error_sent 404, fn ->
        get conn, project_folder_path(conn, :show, -1, folder)
      end
    end

    test "returns 404 when the folder does not exist", %{conn: conn, user: user} do
      project = create_project_for_user(user)

      assert_error_sent 404, fn ->
        get conn, project_folder_path(conn, :show, project, -1)
      end
    end

    test "forbid index access if the project does not belong to the current user", %{conn: conn} do
      folder = insert(:folder)

      assert_error_sent :forbidden, fn ->
        get conn, project_folder_path(conn, :show, folder.project, folder)
      end
    end

  end

  describe "create" do

    test "creates and renders resource when data is valid", %{conn: conn, user: user} do
      project = create_project_for_user(user)

      conn = post conn, project_folder_path(conn, :create, project.id), folder: Map.merge(@valid_attrs, %{project_id: project.id})
      response = json_response(conn, 201)
      assert response["data"]["id"]
      assert Repo.get_by(Folder, @valid_attrs)
    end

  end

  describe "delete:" do
    test "deletes chosen resource", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      folder1 = insert(:folder, project: project)
      folder2 = insert(:folder, project: project)

      assert Repo.get(Folder, folder1.id)
      assert Repo.get(Folder, folder2.id)

      conn = delete conn, project_folder_path(conn, :delete, project, folder1)
      assert response(conn, 204)

      refute Repo.get(Folder, folder1.id)
      assert Repo.get(Folder, folder2.id)
    end

    test "rejects delete if the project doesn't belong to the current user", %{conn: conn} do
      project = insert(:project)
      folder = insert(:folder, project: project)
      assert_error_sent :forbidden, fn ->
        delete conn, project_folder_path(conn, :delete, project, folder)
      end
    end

    test "rejects delete if the folder has surveys", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      folder = insert(:folder, project: project)
      insert(:survey, project: project, folder_id: folder.id)

      conn = delete conn, project_folder_path(conn, :delete, project, folder)

      assert json_response(conn, 422) == %{"errors" => %{"surveys" => ["There are still surveys in this folder"]}}
      assert Repo.get(Folder, folder.id)
    end

    test "rejects delete for a project reader", %{conn: conn, user: user} do
      project = create_project_for_user(user, level: "reader")
      folder = insert(:folder, project: project)

      assert_error_sent :forbidden, fn ->
        delete conn, project_folder_path(conn, :delete, project, folder)
      end
    end

    test "rejects delete if project is archived", %{conn: conn, user: user} do
      project = create_project_for_user(user, archived: true)
      folder = insert(:folder, project: project)

      assert_error_sent :forbidden, fn ->
        delete conn, project_folder_path(conn, :delete, project, folder)
      end
    end

  end

  describe "set_name" do
    test "set name of a folder", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      folder = insert(:folder, project: project)

      conn = post conn, project_folder_folder_path(conn, :set_name, project, folder), name: "new name"

      assert response(conn, 204)
      assert Repo.get(Folder, folder.id).name == "new name"
    end

    test "rejects set_name if the folder doesn't belong to the current user", %{conn: conn} do
      folder = insert(:folder)

      assert_error_sent :forbidden, fn ->
        post conn, project_folder_folder_path(conn, :set_name, folder.project, folder), name: "new name"
      end
    end

    test "rejects set_name for a project reader", %{conn: conn, user: user} do
      project = create_project_for_user(user, level: "reader")
      folder = insert(:folder, project: project)

      assert_error_sent :forbidden, fn ->
        post conn, project_folder_folder_path(conn, :set_name, folder.project, folder), name: "new name"
      end
    end

    test "rejects set_name if project is archived", %{conn: conn, user: user} do
      project = create_project_for_user(user, archived: true)
      folder = insert(:folder, project: project)

      assert_error_sent :forbidden, fn ->
        post conn, project_folder_folder_path(conn, :set_name, folder.project, folder), name: "new name"
      end
    end

    test "rejects set_name if empty", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      folder = insert(:folder, project: project)

      conn = post conn, project_folder_folder_path(conn, :set_name, project, folder), name: ""

      assert json_response(conn, 422) == %{"errors" => %{"name" => ["can't be blank"]}}
      assert Repo.get(Folder, folder.id).name == folder.name
    end

  end

end
