defmodule Ask.ShortLinkControllerTest do
  use Ask.ConnCase
  use Ask.TestHelpers

  alias Ask.{ShortLink, Survey}

  setup %{conn: conn} do
    user = insert(:user)
    conn = conn
      |> put_req_header("accept", "application/json")
    {:ok, conn: conn, user: user}
  end

  test "render surveys if the link specifies that endpoint even if there is no current user", %{conn: conn, user: user} do

    project = create_project_for_user(user)
    survey = insert(:survey, project: project)
    survey = Survey |> Repo.get(survey.id)

    {:ok, link} = ShortLink.generate_link("name", "/api/v1/projects/#{project.id}/surveys")

    conn = get conn, short_link_path(conn, :access, link.hash)

    assert json_response(conn, 200)["data"] == [
      %{"cutoff" => survey.cutoff, "id" => survey.id, "mode" => survey.mode, "name" => survey.name, "description" => nil, "project_id" => project.id, "state" => "not_ready", "locked" => false, "exit_code" => nil, "exit_message" => nil, "schedule" => %{"blocked_days" => [], "day_of_week" => %{"fri" => true, "mon" => true, "sat" => true, "sun" => true, "thu" => true, "tue" => true, "wed" => true}, "end_time" => "23:59:59", "start_time" => "00:00:00", "start_date" => nil, "end_date" => nil, "timezone" => "Etc/UTC"}, "next_schedule_time" => nil, "down_channels" => [], "started_at" => nil, "ended_at" => nil, "updated_at" => DateTime.to_iso8601(survey.updated_at), "folder_id" => nil, "first_window_started_at" => nil, "is_panel_survey" => false, "is_repeatable" => false, "panel_survey_of" => nil, "last_window_ends_at" => nil}
    ]
  end
end
