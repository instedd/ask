defmodule Ask.MembershipControllerTest do

  import Ecto.Query

  use Ask.ConnCase
  use Ask.TestHelpers

  alias Ask.{ProjectMembership}

  setup %{conn: conn} do
    user = insert(:user)
    conn = conn
      |> put_private(:test_user, user)
      |> put_req_header("accept", "application/json")

    {:ok, conn: conn, user: user}
  end

  test "removes member", %{conn: conn, user: user} do
    project = create_project_for_user(user)
    other_user = insert(:user, name: "user2", email: "user2@suveda.instedd.org")
    other_membership = %{"user_id" => other_user.id, "project_id" => project.id, "level" => "editor"}
    ProjectMembership.changeset(%ProjectMembership{}, other_membership) |> Repo.insert

    post conn, project_membership_remove_path(conn, :remove, project.id), user_id: other_user.id
    ProjectMembership |> Repo.all |> Repo.preload(:user)

    assert !(ProjectMembership |> Repo.all |> Enum.any?( fn pm -> pm.user_id == other_user.id end))
  end

  test "updates member's level", %{conn: conn, user: user} do
    project = create_project_for_user(user)
    other_user = insert(:user, name: "user2", email: "user2@suveda.instedd.org")
    other_membership = %{"user_id" => other_user.id, "project_id" => project.id, "level" => "editor"}
    ProjectMembership.changeset(%ProjectMembership{}, other_membership) |> Repo.insert

    post conn, project_membership_update_path(conn, :update, project.id), user_id: other_user.id, new_level: "reader"

    updated_membership = Repo.one(from p in ProjectMembership, where: p.user_id == ^other_user.id)
    assert updated_membership.level == "reader"
  end
end
