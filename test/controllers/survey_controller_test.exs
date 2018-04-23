defmodule Ask.SurveyControllerTest do
  use Ask.ConnCase
  use Ask.TestHelpers
  use Ask.DummySteps

  alias Ask.{Survey, Project, RespondentGroup, Respondent, Response, Channel, SurveyQuestionnaire, RespondentDispositionHistory, TestChannel, RespondentGroupChannel, ShortLink, ActivityLog}
  alias Ask.Runtime.{Flow, Session}
  alias Ask.Runtime.SessionModeProvider

  @valid_attrs %{name: "some content"}
  @invalid_attrs %{cutoff: -1}

  setup %{conn: conn} do
    user = insert(:user)
    conn = conn
      |> put_private(:test_user, user)
      |> put_req_header("accept", "application/json")
    {:ok, conn: conn, user: user}
  end

  describe "index" do
    test "returns code 200 and empty list if there are no entries", %{conn: conn, user: user} do
      project = create_project_for_user(user)

      conn = get conn, project_survey_path(conn, :index, project.id)

      assert json_response(conn, 200)["data"] == []
    end

    test "lists surveys", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)
      survey = Survey |> Repo.get(survey.id)

      conn = get conn, project_survey_path(conn, :index, project.id)

      assert json_response(conn, 200)["data"] == [
        %{"cutoff" => survey.cutoff, "id" => survey.id, "mode" => survey.mode, "name" => survey.name, "project_id" => project.id, "state" => "not_ready", "exit_code" => nil, "exit_message" => nil, "schedule" => %{"blocked_days" => [], "day_of_week" => %{"fri" => true, "mon" => true, "sat" => true, "sun" => true, "thu" => true, "tue" => true, "wed" => true}, "end_time" => "23:59:59", "start_time" => "00:00:00", "timezone" => "Etc/UTC"}, "next_schedule_time" => nil, "updated_at" => NaiveDateTime.to_iso8601(survey.updated_at)}
      ]
    end

    test "list only running surveys", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      insert(:survey, project: project, state: "terminated", exit_code: 0)
      survey = insert(:survey, project: project, state: "running")
      survey = Survey |> Repo.get(survey.id)

      conn = get conn, project_survey_path(conn, :index, project.id, state: "running")

      assert json_response(conn, 200)["data"] == [
        %{"cutoff" => survey.cutoff, "id" => survey.id, "mode" => survey.mode, "name" => survey.name, "project_id" => project.id, "state" => "running", "exit_code" => nil, "exit_message" => nil, "schedule" => %{"blocked_days" => [], "day_of_week" => %{"fri" => true, "mon" => true, "sat" => true, "sun" => true, "thu" => true, "tue" => true, "wed" => true}, "end_time" => "23:59:59", "start_time" => "00:00:00", "timezone" => "Etc/UTC"}, "next_schedule_time" => nil, "updated_at" => NaiveDateTime.to_iso8601(survey.updated_at)}
      ]
    end

    test "list only completed surveys", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      insert(:survey, project: project, state: "running")
      survey = insert(:survey, project: project, state: "terminated", exit_code: 0)
      survey = Survey |> Repo.get(survey.id)

      conn = get conn, project_survey_path(conn, :index, project.id, state: "completed")

      assert json_response(conn, 200)["data"] == [
        %{"cutoff" => survey.cutoff, "id" => survey.id, "mode" => survey.mode, "name" => survey.name, "project_id" => project.id, "state" => "terminated", "exit_code" => 0, "exit_message" => nil, "schedule" => %{"blocked_days" => [], "day_of_week" => %{"fri" => true, "mon" => true, "sat" => true, "sun" => true, "thu" => true, "tue" => true, "wed" => true}, "end_time" => "23:59:59", "start_time" => "00:00:00", "timezone" => "Etc/UTC"}, "next_schedule_time" => nil, "updated_at" => NaiveDateTime.to_iso8601(survey.updated_at)}
      ]
    end

    test "list surveys with filter by update timestamp", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      insert(:survey, project: project)
      survey = insert(:survey, project: project, updated_at: Timex.shift(Timex.now, hours: 2, minutes: 3), state: "running" )
      survey = Survey |> Repo.get(survey.id)

      conn = get conn, project_survey_path(conn, :index, project.id, %{"since" => Timex.format!(Timex.shift(Timex.now, hours: 2), "%FT%T%:z", :strftime)})

      assert json_response(conn, 200)["data"] == [
        %{"cutoff" => survey.cutoff, "id" => survey.id, "mode" => survey.mode, "name" => survey.name, "project_id" => project.id, "state" => "running", "exit_code" => nil, "exit_message" => nil, "schedule" => %{"blocked_days" => [], "day_of_week" => %{"fri" => true, "mon" => true, "sat" => true, "sun" => true, "thu" => true, "tue" => true, "wed" => true}, "end_time" => "23:59:59", "start_time" => "00:00:00", "timezone" => "Etc/UTC"}, "next_schedule_time" => nil, "updated_at" => NaiveDateTime.to_iso8601(survey.updated_at)}
      ]
    end

    test "returns 404 when the project does not exist", %{conn: conn} do
      assert_error_sent 404, fn ->
        get conn, project_survey_path(conn, :index, -1)
      end
    end

    test "forbid index access if the project does not belong to the current user", %{conn: conn} do
      survey = insert(:survey)

      assert_error_sent :forbidden, fn ->
        get conn, project_survey_path(conn, :index, survey.project)
      end
    end
  end

  describe "show" do
    test "shows chosen resource", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)
      survey = Survey |> Repo.get(survey.id)

      conn = get conn, project_survey_path(conn, :show, project, survey)

      assert json_response(conn, 200)["data"] == %{"id" => survey.id,
        "name" => survey.name,
        "mode" => survey.mode,
        "project_id" => survey.project_id,
        "questionnaire_ids" => [],
        "cutoff" => nil,
        "count_partial_results" => false,
        "state" => "not_ready",
        "exit_code" => nil,
        "exit_message" => nil,
        "schedule" => %{
          "day_of_week" => %{
            "fri" => true, "mon" => true, "sat" => true, "sun" => true, "thu" => true, "tue" => true, "wed" => true
          },
          "start_time" => "00:00:00",
          "end_time" => "23:59:59",
          "timezone" => "Etc/UTC",
          "blocked_days" => []
        },
        "started_at" => "",
        "ivr_retry_configuration" => nil,
        "sms_retry_configuration" => nil,
        "mobileweb_retry_configuration" => nil,
        "fallback_delay" => nil,
        "updated_at" => NaiveDateTime.to_iso8601(survey.updated_at),
        "quotas" => %{
          "vars" => [],
          "buckets" => []
        },
        "links" => [],
        "comparisons" => [],
        "next_schedule_time" => nil,
      }
    end

    test "shows chosen resource with buckets", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project, quota_vars: ["gender", "smokes"])
      survey = Survey |> Repo.get(survey.id)
      insert(:quota_bucket, survey: survey, condition: %{gender: "male", smokes: "no"}, quota: 10, count: 3)
      insert(:quota_bucket, survey: survey, condition: %{gender: "male", smokes: "yes"}, quota: 20)
      insert(:quota_bucket, survey: survey, condition: %{gender: "female", smokes: "no"}, quota: 30, count: 1)
      insert(:quota_bucket, survey: survey, condition: %{gender: "female", smokes: "yes"}, quota: 40)

      conn = get conn, project_survey_path(conn, :show, project, survey)

      assert json_response(conn, 200)["data"] == %{"id" => survey.id,
        "name" => survey.name,
        "mode" => survey.mode,
        "project_id" => survey.project_id,
        "questionnaire_ids" => [],
        "cutoff" => nil,
        "count_partial_results" => false,
        "state" => "not_ready",
        "exit_code" => nil,
        "exit_message" => nil,
        "schedule" => %{
          "day_of_week" => %{
            "fri" => true, "mon" => true, "sat" => true, "sun" => true, "thu" => true, "tue" => true, "wed" => true
          },
          "start_time" => "00:00:00",
          "end_time" => "23:59:59",
          "timezone" => "Etc/UTC",
          "blocked_days" => []
        },
        "started_at" => "",
        "ivr_retry_configuration" => nil,
        "sms_retry_configuration" => nil,
        "mobileweb_retry_configuration" => nil,
        "fallback_delay" => nil,
        "updated_at" => NaiveDateTime.to_iso8601(survey.updated_at),
        "quotas" => %{
          "vars" => ["gender", "smokes"],
          "buckets" => [
            %{
              "condition" => [%{"store" => "smokes", "value" => "no"}, %{"store" => "gender", "value" => "male"}],
              "quota" => 10,
              "count" => 3
            },
            %{
              "condition" => [%{"store" => "smokes", "value" => "yes"}, %{"store" => "gender", "value" => "male"}],
              "quota" => 20,
              "count" => 0
            },
            %{
              "condition" => [%{"store" => "smokes", "value" => "no"}, %{"store" => "gender", "value" => "female"}],
              "quota" => 30,
              "count" => 1
            },
            %{
              "condition" => [%{"store" => "smokes", "value" => "yes"}, %{"store" => "gender", "value" => "female"}],
              "quota" => 40,
              "count" => 0
            },
          ]
        },
        "links" => [],
        "comparisons" => [],
        "next_schedule_time" => nil
      }
    end

    test "shows chosen resource with download links", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)
      survey = Survey |> Repo.get(survey.id)
      {:ok, result_link} = ShortLink.generate_link(Survey.link_name(survey, :results), "foo")
      {:ok, incentives_link} = ShortLink.generate_link(Survey.link_name(survey, :incentives), "bar")
      {:ok, interactions_link} = ShortLink.generate_link(Survey.link_name(survey, :interactions), "baz")
      {:ok, disposition_history_link} = ShortLink.generate_link(Survey.link_name(survey, :disposition_history), "bae")

      conn = get conn, project_survey_path(conn, :show, project, survey)

      assert json_response(conn, 200)["data"] == %{"id" => survey.id,
        "name" => survey.name,
        "mode" => survey.mode,
        "project_id" => survey.project_id,
        "questionnaire_ids" => [],
        "cutoff" => nil,
        "count_partial_results" => false,
        "state" => "not_ready",
        "exit_code" => nil,
        "exit_message" => nil,
        "schedule" => %{
          "day_of_week" => %{
            "fri" => true, "mon" => true, "sat" => true, "sun" => true, "thu" => true, "tue" => true, "wed" => true
          },
          "start_time" => "00:00:00",
          "end_time" => "23:59:59",
          "timezone" => "Etc/UTC",
          "blocked_days" => []
        },
        "started_at" => "",
        "ivr_retry_configuration" => nil,
        "sms_retry_configuration" => nil,
        "mobileweb_retry_configuration" => nil,
        "fallback_delay" => nil,
        "updated_at" => NaiveDateTime.to_iso8601(survey.updated_at),
        "quotas" => %{
          "vars" => [],
          "buckets" => []
        },
        "links" => [
          %{
            "name" => "survey/#{survey.id}/results",
            "url" => "#{Ask.Endpoint.url}/link/#{result_link.hash}"
          },
          %{
            "name" => "survey/#{survey.id}/incentives",
            "url" => "#{Ask.Endpoint.url}/link/#{incentives_link.hash}"
          },
          %{
            "name" => "survey/#{survey.id}/interactions",
            "url" => "#{Ask.Endpoint.url}/link/#{interactions_link.hash}"
          },
          %{
            "name" => "survey/#{survey.id}/disposition_history",
            "url" => "#{Ask.Endpoint.url}/link/#{disposition_history_link.hash}"
          },
        ],
        "comparisons" => [],
        "next_schedule_time" => nil,
      }
    end

    test "shows chosen resource with available links if reader", %{conn: conn, user: user} do
      project = create_project_for_user(user, level: "reader")
      survey = insert(:survey, project: project)
      survey = Survey |> Repo.get(survey.id)
      {:ok, result_link} = ShortLink.generate_link(Survey.link_name(survey, :results), "foo")
      {:ok, _incentives_link} = ShortLink.generate_link(Survey.link_name(survey, :incentives), "bar")
      {:ok, _interactions_link} = ShortLink.generate_link(Survey.link_name(survey, :interactions), "baz")
      {:ok, disposition_history_link} = ShortLink.generate_link(Survey.link_name(survey, :disposition_history), "bae")

      conn = get conn, project_survey_path(conn, :show, project, survey)

      assert json_response(conn, 200)["data"] == %{"id" => survey.id,
        "name" => survey.name,
        "mode" => survey.mode,
        "project_id" => survey.project_id,
        "questionnaire_ids" => [],
        "cutoff" => nil,
        "count_partial_results" => false,
        "state" => "not_ready",
        "exit_code" => nil,
        "exit_message" => nil,
        "schedule" => %{
          "day_of_week" => %{
            "fri" => true, "mon" => true, "sat" => true, "sun" => true, "thu" => true, "tue" => true, "wed" => true
          },
          "start_time" => "00:00:00",
          "end_time" => "23:59:59",
          "timezone" => "Etc/UTC",
          "blocked_days" => []
        },
        "started_at" => "",
        "ivr_retry_configuration" => nil,
        "sms_retry_configuration" => nil,
        "mobileweb_retry_configuration" => nil,
        "fallback_delay" => nil,
        "updated_at" => NaiveDateTime.to_iso8601(survey.updated_at),
        "quotas" => %{
          "vars" => [],
          "buckets" => []
        },
        "links" => [
          %{
            "name" => "survey/#{survey.id}/results",
            "url" => "#{Ask.Endpoint.url}/link/#{result_link.hash}"
          },
          %{
            "name" => "survey/#{survey.id}/disposition_history",
            "url" => "#{Ask.Endpoint.url}/link/#{disposition_history_link.hash}"
          },
        ],
        "comparisons" => [],
        "next_schedule_time" => nil,
      }
    end

    test "renders page not found when id is nonexistent", %{conn: conn} do
      assert_error_sent 404, fn ->
        get conn, project_survey_path(conn, :show, -1, -1)
      end
    end

    test "forbid access to survey if the project does not belong to the current user", %{conn: conn} do
      survey = insert(:survey)

      assert_error_sent :forbidden, fn ->
        get conn, project_survey_path(conn, :show, survey.project, survey)
      end
    end
  end

  describe "create" do
    test "creates and renders resource when data is valid", %{conn: conn, user: user} do
      project = create_project_for_user(user)

      conn = post conn, project_survey_path(conn, :create, project.id)

      assert json_response(conn, 201)["data"]["id"]
      assert Repo.get_by(Survey, %{project_id: project.id})
    end

    test "forbids creation of survey for a project that belongs to another user", %{conn: conn} do
      project = insert(:project)

      assert_error_sent :forbidden, fn ->
        post conn, project_survey_path(conn, :create, project.id), survey: @valid_attrs
      end
    end

    test "forbids creation of survey for a project reader", %{conn: conn, user: user} do
      project = create_project_for_user(user, level: "reader")

      assert_error_sent :forbidden, fn ->
        post conn, project_survey_path(conn, :create, project.id), survey: @valid_attrs
      end
    end

    test "updates project updated_at when survey is created", %{conn: conn, user: user} do
      datetime = Ecto.DateTime.cast!("2000-01-01 00:00:00")
      project = create_project_for_user(user)
      post conn, project_survey_path(conn, :create, project.id)

      project = Project |> Repo.get(project.id)
      assert Ecto.DateTime.compare((project.updated_at |> NaiveDateTime.to_erl |> Ecto.DateTime.from_erl), datetime) == :gt
    end

    test "forbids creation if project is archived", %{conn: conn, user: user} do
      project = create_project_for_user(user, archived: true)
      assert_error_sent :forbidden, fn ->
        post conn, project_survey_path(conn, :create, project.id)
      end
    end
  end

  describe "update" do
    test "updates and renders chosen resource when data is valid", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)

      conn = put conn, project_survey_path(conn, :update, project, survey), survey: @valid_attrs

      assert json_response(conn, 200)["data"]["id"]
      assert Repo.get_by(Survey, @valid_attrs)
    end

    test "updates schedule when data is valid", %{conn: conn, user: user} do
      [project, questionnaire, _] = prepare_for_state_update(user)
      survey = insert(:survey, project: project, questionnaires: [questionnaire])

      conn = put conn, project_survey_path(conn, :update, project, survey), survey: %{schedule: completed_schedule()}

      assert json_response(conn, 200)["data"]["schedule"]["day_of_week"]["sun"] == true
    end

    test "updates cutoff when channels are included in params", %{conn: conn, user: user} do
      [project, questionnaire, channel] = prepare_for_state_update(user)
      survey = insert(:survey, project: project, questionnaires: [questionnaire])
      create_group(survey, channel)

      conn = put conn, project_survey_path(conn, :update, project, survey), survey: %{cutoff: 4, channels: [channel.id]}

      assert json_response(conn, 200)["data"]["cutoff"] == 4
    end

    test "does not update chosen resource and renders errors when data is invalid", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)

      conn = put conn, project_survey_path(conn, :update, survey.project, survey), survey: @invalid_attrs

      assert json_response(conn, 422)["errors"] != %{}
    end

    test "saves quota_buckets and quota_vars", %{conn: conn, user: user} do
      [project, questionnaire, _] = prepare_for_state_update(user)
      survey = insert(:survey, project: project, questionnaires: [questionnaire])

      conn2 = put conn, project_survey_path(conn, :update, project, survey), survey: %{quotas: %{vars: ["Smokes", "Exercises"], buckets: [
        %{
          "condition" => [%{"store" => "Exercises", "value" => "No"}, %{"store" => "Smokes", "value" => "No"}],
          "quota" => 10,
          "count" => 3
        },
        %{
          "condition" => [%{"store" => "Exercises", "value" => "No"}, %{"store" => "Smokes", "value" => "Yes"}],
          "quota" => 20
        },
        %{
          "condition" => [%{"store" => "Exercises", "value" => "Yes"}, %{"store" => "Smokes", "value" => "No"}],
          "quota" => 30
        },
        %{
          "condition" => [%{"store" => "Exercises", "value" => "Yes"}, %{"store" => "Smokes", "value" => "Yes"}],
          "quota" => 40
        },
      ]}}

      assert json_response(conn2, 200)["data"]["quotas"]["vars"] == ["Smokes", "Exercises"]
      assert json_response(conn2, 200)["data"]["quotas"]["buckets"] == [
        %{
          "condition" => [%{"store" => "Smokes", "value" => "No"}, %{"store" => "Exercises", "value" => "No"}],
          "quota" => 10,
          "count" => 3
        },
        %{
          "condition" => [%{"store" => "Smokes", "value" => "Yes"}, %{"store" => "Exercises", "value" => "No"}],
          "quota" => 20,
          "count" => 0
        },
        %{
          "condition" => [%{"store" => "Smokes", "value" => "No"}, %{"store" => "Exercises", "value" => "Yes"}],
          "quota" => 30,
          "count" => 0
        },
        %{
          "condition" => [%{"store" => "Smokes", "value" => "Yes"}, %{"store" => "Exercises", "value" => "Yes"}],
          "quota" => 40,
          "count" => 0
        },
      ]

      conn = get conn, project_survey_path(conn, :show, project, survey)

      assert json_response(conn, 200)["data"]["quotas"] == %{
        "vars" => ["Smokes", "Exercises"],
        "buckets" => [
          %{
            "condition" => [%{"store" => "Smokes", "value" => "No"}, %{"store" => "Exercises", "value" => "No"}],
            "quota" => 10,
            "count" => 3
          },
          %{
            "condition" => [%{"store" => "Smokes", "value" => "Yes"}, %{"store" => "Exercises", "value" => "No"}],
            "quota" => 20,
            "count" => 0
          },
          %{
            "condition" => [%{"store" => "Smokes", "value" => "No"}, %{"store" => "Exercises", "value" => "Yes"}],
            "quota" => 30,
            "count" => 0
          },
          %{
            "condition" => [%{"store" => "Smokes", "value" => "Yes"}, %{"store" => "Exercises", "value" => "Yes"}],
            "quota" => 40,
            "count" => 0
          },
        ]
      }
    end

    test "replaces quota_buckets when vars are updated", %{conn: conn, user: user}  do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project, quota_vars: ["gender", "smokes"])
      insert(:quota_bucket, survey: survey, condition: %{gender: "male", smokes: "no"}, quota: 10, count: 3)
      insert(:quota_bucket, survey: survey, condition: %{gender: "male", smokes: "yes"}, quota: 20)
      insert(:quota_bucket, survey: survey, condition: %{gender: "female", smokes: "no"}, quota: 30, count: 1)
      insert(:quota_bucket, survey: survey, condition: %{gender: "female", smokes: "yes"}, quota: 40)

      conn = put conn, project_survey_path(conn, :update, project, survey), survey: %{quotas: %{vars: ["Exercises", "Smokes"], buckets: [
        %{
          "condition" => [%{"store" => "Exercises", "value" => "No"}, %{"store" => "Smokes", "value" => "No"}],
          "quota" => 10,
          "count" => 3
        },
        %{
          "condition" => [%{"store" => "Exercises", "value" => "No"}, %{"store" => "Smokes", "value" => "Yes"}],
          "quota" => 20
        },
        %{
          "condition" => [%{"store" => "Exercises", "value" => "Yes"}, %{"store" => "Smokes", "value" => "No"}],
          "quota" => 30
        },
        %{
          "condition" => [%{"store" => "Exercises", "value" => "Yes"}, %{"store" => "Smokes", "value" => "Yes"}],
          "quota" => 40
        },
      ]}}

      assert json_response(conn, 200)["data"]["quotas"]["vars"] == ["Exercises", "Smokes"]
      assert json_response(conn, 200)["data"]["quotas"]["buckets"] == [
        %{
          "condition" => [%{"store" => "Smokes", "value" => "No"}, %{"store" => "Exercises", "value" => "No"}],
          "quota" => 10,
          "count" => 3
        },
        %{
          "condition" => [%{"store" => "Smokes", "value" => "Yes"}, %{"store" => "Exercises", "value" => "No"}],
          "quota" => 20,
          "count" => 0
        },
        %{
          "condition" => [%{"store" => "Smokes", "value" => "No"}, %{"store" => "Exercises", "value" => "Yes"}],
          "quota" => 30,
          "count" => 0
        },
        %{
          "condition" => [%{"store" => "Smokes", "value" => "Yes"}, %{"store" => "Exercises", "value" => "Yes"}],
          "quota" => 40,
          "count" => 0
        },
      ]
    end

    test "rejects update if the survey doesn't belong to the current user", %{conn: conn} do
      survey = insert(:survey)

      assert_error_sent :forbidden, fn ->
        put conn, project_survey_path(conn, :update, survey.project, survey), survey: @invalid_attrs
      end
    end

    test "rejects update for a project reader", %{conn: conn, user: user} do
      project = create_project_for_user(user, level: "reader")
      survey = insert(:survey, project: project)

      assert_error_sent :forbidden, fn ->
        put conn, project_survey_path(conn, :update, survey.project, survey), survey: @invalid_attrs
      end
    end

    test "rejects update if project is archived", %{conn: conn, user: user} do
      project = create_project_for_user(user, archived: true)
      survey = insert(:survey, project: project)

      assert_error_sent :forbidden, fn ->
        put conn, project_survey_path(conn, :update, survey.project, survey), survey: @invalid_attrs
      end
    end

    test "fails if the schedule from is greater or equal to the to", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)

      conn = put conn, project_survey_path(conn, :update, project, survey), survey: Map.merge(@valid_attrs, %{schedule: Map.merge(Ask.Schedule.default(), %{start_time: ~T[02:00:00], end_time: ~T[01:00:00]})})

      assert json_response(conn, 422)["errors"] != %{}
    end

    test "schedule to and from are saved successfully", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)


      conn = put conn, project_survey_path(conn, :update, project, survey), survey: Map.merge(@valid_attrs, %{schedule: %{start_time: "01:00:00", end_time: "02:00:00", blocked_days: [], timezone: "Etc/UTC", day_of_week: Ask.DayOfWeek.every_day()}})

      assert json_response(conn, 200)
      created_survey = Repo.get_by(Survey, %{project_id: project.id})
      assert created_survey.schedule.start_time == ~T[01:00:00]
      assert created_survey.schedule.end_time == ~T[02:00:00]
    end

    test "rejects update with correct error when cutoff field is greater than the max value", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)
      max_int = 2147483648

      conn = put conn, project_survey_path(conn, :update, survey.project, survey), survey: Map.merge(@valid_attrs, %{cutoff: max_int})

      assert json_response(conn, 422)["errors"] != %{cutoff: "must be less than #{max_int}"}
    end

    test "rejects update with correct error when cutoff field is less than zero", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)

      conn = put conn, project_survey_path(conn, :update, survey.project, survey), survey: Map.merge(@valid_attrs, %{cutoff: 0})

      assert json_response(conn, 422)["errors"] != %{cutoff: "must be greater than 0"}
    end

    test "updates project updated_at when survey is updated", %{conn: conn, user: user}  do
      datetime = Ecto.DateTime.cast!("2000-01-01 00:00:00")
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)

      put conn, project_survey_path(conn, :update, survey.project, survey), survey: %{name: "New name"}

      project = Project |> Repo.get(project.id)
      assert Ecto.DateTime.compare((project.updated_at |> NaiveDateTime.to_erl |> Ecto.DateTime.from_erl), datetime) == :gt
    end
  end

  describe "set_name" do
    test "set name of a survey", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)

      conn = post conn, project_survey_survey_path(conn, :set_name, project, survey), name: "new name"

      assert response(conn, 204)
      assert Repo.get(Survey, survey.id).name == "new name"
    end

    test "rejects set_name if the survey doesn't belong to the current user", %{conn: conn} do
      survey = insert(:survey)

      assert_error_sent :forbidden, fn ->
        post conn, project_survey_survey_path(conn, :set_name, survey.project, survey), name: "new name"
      end
    end

    test "rejects set_name for a project reader", %{conn: conn, user: user} do
      project = create_project_for_user(user, level: "reader")
      survey = insert(:survey, project: project)

      assert_error_sent :forbidden, fn ->
        post conn, project_survey_survey_path(conn, :set_name, survey.project, survey), name: "new name"
      end
    end

    test "rejects set_name if project is archived", %{conn: conn, user: user} do
      project = create_project_for_user(user, archived: true)
      survey = insert(:survey, project: project)

      assert_error_sent :forbidden, fn ->
        post conn, project_survey_survey_path(conn, :set_name, survey.project, survey), name: "new name"
      end
    end
  end

  describe "delete" do
    test "deletes chosen resource", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)

      conn = delete conn, project_survey_path(conn, :delete, survey.project, survey)

      assert response(conn, 204)
      refute Repo.get(Survey, survey.id)
    end

    test "forbids delete if the project doesn't belong to the current user", %{conn: conn} do
      survey = insert(:survey)

      assert_error_sent :forbidden, fn ->
        delete conn, project_survey_path(conn, :delete, survey.project, survey)
      end
    end

    test "forbids delete for a project reader", %{conn: conn, user: user} do
      project = create_project_for_user(user, level: "reader")
      survey = insert(:survey, project: project)

      assert_error_sent :forbidden, fn ->
        delete conn, project_survey_path(conn, :delete, survey.project, survey)
      end
    end

    test "forbids delete if project is archived", %{conn: conn, user: user} do
      project = create_project_for_user(user, archived: true)
      survey = insert(:survey, project: project)

      assert_error_sent :forbidden, fn ->
        delete conn, project_survey_path(conn, :delete, survey.project, survey)
      end
    end

    test "reject delete if the survey is running", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project, state: "running")

      conn = delete conn, project_survey_path(conn, :delete, survey.project, survey)

      assert response(conn, :bad_request)
      assert Survey |> Repo.get(survey.id)
    end

    test "updates project updated_at when survey is deleted", %{conn: conn, user: user}  do
      datetime = Ecto.DateTime.cast!("2000-01-01 00:00:00")
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)

      delete conn, project_survey_path(conn, :delete, survey.project, survey)

      project = Project |> Repo.get(project.id)
      assert Ecto.DateTime.compare((project.updated_at |> NaiveDateTime.to_erl |> Ecto.DateTime.from_erl), datetime) == :gt
    end

    test "delete survey and all contents", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)
      channel = insert(:channel, user: user)
      group = create_group(survey, channel)
      respondent = add_respondent_to(group)
      response = insert(:response, respondent: respondent)
      questionnaire = insert(:questionnaire, project: project)
      survey_questionnaire = insert(:survey_questionnaire, survey: survey, questionnaire: questionnaire)
      history = insert(:respondent_disposition_history, respondent: respondent)

      delete conn, project_survey_path(conn, :delete, survey.project, survey)

      refute Survey |> Repo.get(survey.id)
      refute RespondentGroup |> Repo.get(group.id)
      refute Respondent |> Repo.get(respondent.id)
      refute Response |> Repo.get(response.id)
      refute SurveyQuestionnaire |> Repo.get(survey_questionnaire.id)
      refute RespondentDispositionHistory |> Repo.get(history.id)
    end
  end

  describe "changes the survey state when needed" do
    test "updates state when adding questionnaire", %{conn: conn, user: user} do
      [project, questionnaire, channel] = prepare_for_state_update(user)
      survey = insert(:survey, project: project, cutoff: 4, schedule: completed_schedule())
      create_group(survey, channel)

      conn = put conn, project_survey_path(conn, :update, project, survey), survey: %{questionnaire_ids: [questionnaire.id]}

      assert json_response(conn, 200)["data"]["id"]
      new_survey = Repo.get(Survey, survey.id)
      qs = (new_survey |> Repo.preload(:questionnaires)).questionnaires
      assert length(qs) == 1
      assert hd(qs).id == questionnaire.id
      assert new_survey.state == "ready"
    end

    test "updates state when selecting mode", %{conn: conn, user: user} do
      [project, questionnaire, channel] = prepare_for_state_update(user)
      survey = insert(:survey, project: project, questionnaires: [questionnaire], cutoff: 4, schedule: completed_schedule())
      create_group(survey, channel)

      conn = put conn, project_survey_path(conn, :update, project, survey), survey: %{mode: [["sms"]]}

      assert json_response(conn, 200)["data"]["id"]
      new_survey = Repo.get(Survey, survey.id)
      assert new_survey.state == "ready"
    end

    test "updates state when selecting mode, missing channel", %{conn: conn, user: user} do
      [project, questionnaire, channel] = prepare_for_state_update(user)
      survey = insert(:survey, project: project, questionnaires: [questionnaire], cutoff: 4, schedule: completed_schedule())
      create_group(survey, channel)

      conn = put conn, project_survey_path(conn, :update, project, survey), survey: %{mode: [["sms", "ivr"]]}

      assert json_response(conn, 200)["data"]["id"]
      new_survey = Repo.get(Survey, survey.id)
      assert new_survey.state == "not_ready"
    end

    test "updates state when selecting mode, missing channel, multiple modes", %{conn: conn, user: user} do
      [project, questionnaire, channel] = prepare_for_state_update(user)
      survey = insert(:survey, project: project, questionnaires: [questionnaire], cutoff: 4, schedule: completed_schedule())
      create_group(survey, channel)

      conn = put conn, project_survey_path(conn, :update, project, survey), survey: %{mode: [["sms"], ["sms", "ivr"]]}

      assert json_response(conn, 200)["data"]["id"]
      new_survey = Repo.get(Survey, survey.id)
      assert new_survey.state == "not_ready"
    end

    test "updates state when selecting mode, all channels", %{conn: conn, user: user} do
      [project, questionnaire, channel] = prepare_for_state_update(user)
      survey = insert(:survey, project: project, questionnaires: [questionnaire], cutoff: 4, schedule: completed_schedule())
      group = create_group(survey)
      channel2 = insert(:channel, user: user, type: "ivr")
      add_channel_to(group, channel)
      add_channel_to(group, channel2)

      conn = put conn, project_survey_path(conn, :update, project, survey), survey: %{mode: [["sms", "ivr"]]}

      assert json_response(conn, 200)["data"]["id"]
      new_survey = Repo.get(Survey, survey.id)
      assert new_survey.state == "ready"
    end

    test "updates state when adding cutoff", %{conn: conn, user: user} do
      [project, questionnaire, channel] = prepare_for_state_update(user)
      survey = insert(:survey, project: project, questionnaires: [questionnaire], schedule: completed_schedule(), mode: [["sms"]])
      create_group(survey, channel)

      conn = put conn, project_survey_path(conn, :update, project, survey), survey: %{cutoff: 4}

      assert json_response(conn, 200)["data"]["id"]
      new_survey = Repo.get(Survey, survey.id)
      assert new_survey.state == "ready"
    end

    test "changes state to not_ready when an invalid retry attempt configuration is passed", %{conn: conn, user: user} do
      [project, questionnaire, channel] = prepare_for_state_update(user)
      survey = insert(:survey, project: project, cutoff: 4, schedule: completed_schedule(), mode: [["sms"]], questionnaires: [questionnaire])
      create_group(survey, channel)

      conn = put conn, project_survey_path(conn, :update, project, survey), survey: %{sms_retry_configuration: "12j 13p 14q"}

      assert json_response(conn, 200)["data"]["id"]
      new_survey = Repo.get(Survey, survey.id)
      assert new_survey.state == "not_ready"
    end

    test "changes state to not_ready when an invalid fallback delay is passed", %{conn: conn, user: user} do
      [project, questionnaire, channel] = prepare_for_state_update(user)
      survey = insert(:survey, project: project, cutoff: 4, schedule: completed_schedule(), mode: [["sms"]], questionnaires: [questionnaire])
      create_group(survey, channel)

      conn = put conn, project_survey_path(conn, :update, project, survey), survey: %{fallback_delay: "12j"}

      assert json_response(conn, 200)["data"]["id"]
      new_survey = Repo.get(Survey, survey.id)
      assert new_survey.state == "not_ready"
    end

    test "returns state to ready when a valid retry configuration is passed", %{conn: conn, user: user} do
      [project, questionnaire, channel] = prepare_for_state_update(user)
      survey = insert(:survey, project: project, cutoff: 4, schedule: completed_schedule(), mode: [["sms"]], questionnaires: [questionnaire], sms_retry_configuration: "12j 13p 14q")
      create_group(survey, channel)
      new_survey = Repo.get(Survey, survey.id)

      assert new_survey.state == "not_ready"

      conn = put conn, project_survey_path(conn, :update, project, survey), survey: %{sms_retry_configuration: "5m 1h 2d"}

      assert json_response(conn, 200)["data"]["id"]
      new_survey = Repo.get(Survey, survey.id)
      assert new_survey.state == "ready"
    end

    test "updates state when adding a day in schedule", %{conn: conn, user: user} do
      [project, questionnaire, channel] = prepare_for_state_update(user)
      survey = insert(:survey, project: project, questionnaires: [questionnaire], cutoff: 3, mode: [["sms"]])
      create_group(survey, channel)

      conn = put conn,
        project_survey_path(conn, :update, project, survey),
        survey: %{ schedule:
          %{ survey.schedule |
            day_of_week: %Ask.DayOfWeek{mon: true, tue: true}
          }
        }

      assert json_response(conn, 200)["data"]["id"]
      new_survey = Repo.get(Survey, survey.id)
      assert new_survey.state == "ready"
    end

    test "updates state when removing schedule", %{conn: conn, user: user} do
      [project, questionnaire, channel] = prepare_for_state_update(user)
      survey = insert(:survey, project: project, questionnaires: [questionnaire], cutoff: 3, schedule: completed_schedule())
      create_group(survey, channel)

      conn = put conn, project_survey_path(conn, :update, project, survey), survey: %{schedule: incomplete_schedule()}

      assert json_response(conn, 200)["data"]["id"]
      new_survey = Repo.get(Survey, survey.id)
      assert new_survey.state == "not_ready"
    end

    test "updates state when removing questionnaire", %{conn: conn, user: user} do
      [project, questionnaire, channel] = prepare_for_state_update(user)
      survey = insert(:survey, project: project, questionnaires: [questionnaire], cutoff: 4, state: "ready", schedule: completed_schedule())
      create_group(survey, channel)

      assert survey.state == "ready"

      conn = put conn, project_survey_path(conn, :update, project, survey), survey: %{questionnaire_ids: []}

      assert json_response(conn, 200)["data"]["id"]
      new_survey = Repo.get(Survey, survey.id)
      qs = (new_survey |> Repo.preload(:questionnaires)).questionnaires
      assert length(qs) == 0
      assert new_survey.state == "not_ready"
    end

    test "does not update state when adding cutoff if missing questionnaire", %{conn: conn, user: user} do
      [project, _, channel] = prepare_for_state_update(user)
      survey = insert(:survey, project: project, schedule: completed_schedule())

      assert survey.state == "not_ready"

      create_group(survey, channel)

      conn = put conn, project_survey_path(conn, :update, project, survey), survey: %{cutoff: 4}

      assert json_response(conn, 200)["data"]["id"]
      new_survey = Repo.get(Survey, survey.id)
      assert new_survey.state == "not_ready"
    end

    test "does not update state when adding cutoff if missing respondents", %{conn: conn, user: user} do
      [project, questionnaire, _] = prepare_for_state_update(user)
      survey = insert(:survey, project: project, questionnaires: [questionnaire], schedule: completed_schedule())

      assert survey.state == "not_ready"

      conn = put conn, project_survey_path(conn, :update, project, survey), survey: %{cutoff: 4}

      assert json_response(conn, 200)["data"]["id"]
      new_survey = Repo.get(Survey, survey.id)
      assert new_survey.state == "not_ready"
    end

    test "does not update state when adding questionnaire if missing channel", %{conn: conn, user: user} do
      [project, questionnaire, _] = prepare_for_state_update(user)
      survey = insert(:survey, project: project, cutoff: 4, schedule: completed_schedule())
      group = insert(:respondent_group, survey: survey)
      add_respondent_to group

      conn = put conn, project_survey_path(conn, :update, project, survey), survey: %{questionnaire_id: questionnaire.id}

      assert json_response(conn, 200)["data"]["id"]
      new_survey = Repo.get(Survey, survey.id)
      assert new_survey.state == "not_ready"
    end

    test "sets to not ready if comparisons' ratio don't sum 100", %{conn: conn, user: user} do
      [project, questionnaire, channel] = prepare_for_state_update(user)
      survey = insert(:survey, project: project, questionnaires: [questionnaire], cutoff: 3, schedule: completed_schedule(), mode: [["sms"]])
      create_group(survey, channel)

      conn = put conn, project_survey_path(conn, :update, project, survey), survey: %{comparisons: [%{questionnaire_id: questionnaire.id, mode: ["sms"], ratio: 99}]}

      assert json_response(conn, 200)["data"]["id"]
      new_survey = Repo.get(Survey, survey.id)
      assert new_survey.state == "not_ready"
    end

    test "sets to ready if comparisons' ratio sum 100", %{conn: conn, user: user} do
      [project, questionnaire, channel] = prepare_for_state_update(user)
      survey = insert(:survey, project: project, questionnaires: [questionnaire], cutoff: 3, schedule: completed_schedule(), mode: [["sms"]])
      create_group(survey, channel)

      conn = put conn, project_survey_path(conn, :update, project, survey), survey: %{comparisons: [%{questionnaire_id: questionnaire.id, mode: ["sms"], ratio: 100}]}

      assert json_response(conn, 200)["data"]["id"]
      new_survey = Repo.get(Survey, survey.id)
      assert new_survey.state == "ready"
    end

    test "changes state to not_ready when questionnaire is invalid", %{conn: conn, user: user} do
      [project, questionnaire, channel] = prepare_for_state_update(user)
      survey = insert(:survey, project: project, cutoff: 4, schedule: completed_schedule(), mode: [["sms"]], questionnaires: [])
      create_group(survey, channel)
      questionnaire |> Ask.Questionnaire.changeset(%{"valid" => false}) |> Repo.update!

      conn = put conn, project_survey_path(conn, :update, project, survey), survey: %{questionnaire_ids: [questionnaire.id]}

      assert json_response(conn, 200)["data"]["id"]
      new_survey = Repo.get(Survey, survey.id)
      assert new_survey.state == "not_ready"
    end

    test "changes state to not_ready when survey mode doesn't match questionnaire mode", %{conn: conn, user: user} do
      [project, questionnaire, channel] = prepare_for_state_update(user)
      questionnaire |> Ask.Questionnaire.changeset(%{"modes" => ["ivr"]}) |> Repo.update!
      survey = insert(:survey, project: project, cutoff: 4, schedule: completed_schedule(), mode: [["ivr"]], questionnaires: [questionnaire])
      create_group(survey, channel)

      conn = put conn, project_survey_path(conn, :update, project, survey), survey: %{mode: [["sms"]]}

      assert json_response(conn, 200)["data"]["id"]
      new_survey = Repo.get(Survey, survey.id)
      assert new_survey.state == "not_ready"
    end
  end

  test "prevents launching a survey that is not in the ready state", %{conn: conn, user: user} do
    project = create_project_for_user(user)
    survey = insert(:survey, project: project, state: "not_ready")

    conn = post conn, project_survey_survey_path(conn, :launch, survey.project, survey)

    assert response(conn, 422)
  end

  test "when launching a survey, it sets the state to running", %{conn: conn, user: user} do
    project = create_project_for_user(user)
    survey = insert(:survey, project: project, state: "ready")

    conn = post conn, project_survey_survey_path(conn, :launch, survey.project, survey)

    assert json_response(conn, 200)
    assert Repo.get(Survey, survey.id).state == "running"
  end

  test "when launching a survey, it creates questionnaire snapshots", %{conn: conn, user: user} do
    project = create_project_for_user(user)
    questionnaire = insert(:questionnaire, name: "test", project: project, steps: @dummy_steps)
    questionnaire |> Ask.Questionnaire.recreate_variables!
    survey = insert(:survey, project: project, state: "ready", questionnaires: [questionnaire], comparisons: [
        %{"mode" => ["sms"], "questionnaire_id" => questionnaire.id, "one" => 50},
        %{"mode" => ["sms"], "questionnaire_id" => questionnaire.id, "two" => 40},
      ])

    conn = post conn, project_survey_survey_path(conn, :launch, survey.project, survey)

    assert json_response(conn, 200)
    survey = Repo.get(Survey, survey.id)
    |> Repo.preload(:questionnaires)
    qs = survey.questionnaires
    assert length(qs) == 1
    q = hd(qs)
    assert q.snapshot_of == questionnaire.id
    assert q.name == questionnaire.name
    assert q.steps == questionnaire.steps
    assert q.modes == questionnaire.modes
    assert survey.comparisons == [
      %{"mode" => ["sms"], "questionnaire_id" => q.id, "one" => 50},
      %{"mode" => ["sms"], "questionnaire_id" => q.id, "two" => 40},
    ]
  end

  test "survey view contains questionnaire modes for each questionnaire after launching a survey", %{conn: conn, user: user} do
    project = create_project_for_user(user)
    questionnaire = insert(:questionnaire, name: "test", project: project, steps: @dummy_steps, modes: ["sms", "ivr"])
    survey_ready = insert(:survey, project: project, state: "ready", questionnaires: [questionnaire])
    post conn, project_survey_survey_path(conn, :launch, survey_ready.project, survey_ready)
    survey_launched = Repo.get(Survey, survey_ready.id)

    conn = get conn, project_survey_path(conn, :show, project, survey_launched)

    questionnaire_snapshot_id = ((survey_launched |> Repo.preload(:questionnaires)).questionnaires |> hd).id |> Integer.to_string
    response = json_response(conn, 200)["data"]
    assert response["questionnaires"][questionnaire_snapshot_id]["modes"] == questionnaire.modes
  end

  test "forbids launch for project reader", %{conn: conn, user: user} do
    project = create_project_for_user(user, level: "reader")
    survey = insert(:survey, project: project, state: "ready")

    assert_error_sent :forbidden, fn ->
      post conn, project_survey_survey_path(conn, :launch, survey.project, survey)
    end
  end

  test "forbids launch if project is archived", %{conn: conn, user: user} do
    project = create_project_for_user(user, archived: true)
    survey = insert(:survey, project: project, state: "ready")

    assert_error_sent :forbidden, fn ->
      post conn, project_survey_survey_path(conn, :launch, survey.project, survey)
    end
  end

  test "launches a survey with channel", %{conn: conn, user: user} do
    project = create_project_for_user(user)
    survey = insert(:survey, project: project, state: "ready")
    test_channel = TestChannel.new
    channel = insert(:channel, settings: test_channel |> TestChannel.settings, type: "sms")
    create_group(survey, channel)

    conn = post conn, project_survey_survey_path(conn, :launch, survey.project, survey)

    assert json_response(conn, 200)
    assert Repo.get(Survey, survey.id).state == "running"

    received_at_uri = "#{Ask.Endpoint.url}/callbacks/test"
    assert_received [:prepare, ^test_channel, received_at_uri]
  end

  test "sets started_at with proper datetime value when a survey is launched", %{conn: conn, user: user} do
    now = Timex.now
    project = create_project_for_user(user)
    survey = insert(:survey, project: project, state: "ready")

    post conn, project_survey_survey_path(conn, :launch, survey.project, survey)

    started_at = Repo.get(Survey, survey.id).started_at
    assert (Timex.between?(started_at, Timex.shift(now, seconds: -3), Timex.shift(now, seconds: 3)))
  end

  test "updates project updated_at when a survey is launched", %{conn: conn, user: user}  do
    datetime = Ecto.DateTime.cast!("2000-01-01 00:00:00")
    project = create_project_for_user(user)
    survey = insert(:survey, project: project, state: "ready")

    post conn, project_survey_survey_path(conn, :launch, survey.project, survey)

    project = Project |> Repo.get(project.id)
    assert Ecto.DateTime.compare((project.updated_at |> NaiveDateTime.to_erl |> Ecto.DateTime.from_erl), datetime) == :gt
  end

  test "stops survey", %{conn: conn, user: user} do
    project = create_project_for_user(user)
    questionnaire = insert(:questionnaire, name: "test", project: project)
    survey = insert(:survey, project: project, state: "running")
    test_channel = TestChannel.new(false)
    channel = insert(:channel, settings: test_channel |> TestChannel.settings, type: "sms")
    group = create_group(survey, channel)
    insert_list(10, :respondent, survey: survey, state: "pending")
    r1 = insert(:respondent, survey: survey, state: "active", respondent_group: group)
    insert_list(3, :respondent, survey: survey, state: "stalled", timeout_at: Timex.now)
    channel_state = %{"call_id" => 123}
    session = %Session{
      current_mode: SessionModeProvider.new("sms", channel, []),
      channel_state: channel_state,
      respondent: r1,
      flow: %Flow{questionnaire: questionnaire},
      schedule: survey.schedule,
    }
    session = Session.dump(session)
    r1 |> Ask.Respondent.changeset(%{session: session}) |> Repo.update!

    conn = post conn, project_survey_survey_path(conn, :stop, survey.project, survey)

    assert json_response(conn, 200)
    survey = Repo.get(Survey, survey.id)
    assert Survey.cancelled?(survey)
    assert length(Repo.all(from(r in Ask.Respondent, where: (r.state == "cancelled" and is_nil(r.session) and is_nil(r.timeout_at))))) == 4
    assert_receive [:cancel_message, ^test_channel, ^channel_state]
  end

  test "stops respondents only for the stopped survey", %{conn: conn, user: user} do
    project = create_project_for_user(user)
    questionnaire = insert(:questionnaire, name: "test", project: project)
    survey  = insert(:survey, project: project, state: "running")
    survey2 = insert(:survey, project: project, state: "running")
    test_channel = TestChannel.new(false)
    channel = insert(:channel, settings: test_channel |> TestChannel.settings, type: "sms")
    group = create_group(survey, channel)
    r1 = insert(:respondent, survey: survey, state: "active", respondent_group: group)
    insert_list(3, :respondent, survey: survey, state: "stalled", respondent_group: group, timeout_at: Timex.now)
    insert_list(4, :respondent, survey: survey2, state: "active", session: %{})
    insert_list(2, :respondent, survey: survey2, state: "stalled", timeout_at: Timex.now)
    channel_state = %{"call_id" => 123}
    session = %Session{
      current_mode: SessionModeProvider.new("sms", channel, []),
      channel_state: channel_state,
      respondent: r1,
      flow: %Flow{questionnaire: questionnaire},
      schedule: survey.schedule,
    }
    session = Session.dump(session)
    r1 |> Ask.Respondent.changeset(%{session: session}) |> Repo.update!

    conn = post conn, project_survey_survey_path(conn, :stop, survey.project, survey)

    assert json_response(conn, 200)
    assert Repo.get(Survey, survey2.id).state == "running"
    assert length(Repo.all(from(r in Ask.Respondent, where: (r.state == "active" or r.state == "stalled" )))) == 6
    assert_receive [:cancel_message, ^test_channel, ^channel_state]
  end

  test "stopping completed survey still works (#736)", %{conn: conn, user: user} do
    project = create_project_for_user(user)
    survey = insert(:survey, project: project, state: "terminated", exit_code: 0, exit_message: "Successfully completed")

    conn = post conn, project_survey_survey_path(conn, :stop, survey.project, survey)

    assert json_response(conn, 200)
    survey = Repo.get(Survey, survey.id)
    assert Survey.completed?(survey)
  end

  test "stopping cancelled survey still works (#736)", %{conn: conn, user: user} do
    project = create_project_for_user(user)
    survey = insert(:survey, project: project, state: "terminated", exit_code: 1)

    conn = post conn, project_survey_survey_path(conn, :stop, project, survey)

    assert json_response(conn, 200)
    survey = Repo.get(Survey, survey.id)
    assert Survey.cancelled?(survey)
  end

  describe "download links" do
    test "results link generation", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)

      response = get conn, project_survey_links_path(conn, :create_link, project, survey, "results")

      link = ShortLink |> Repo.one

      assert json_response(response, 200) == %{
        "name" => "survey/#{survey.id}/results",
        "url" => "#{Ask.Endpoint.url}/link/#{link.hash}"
      }

      assert link.target == "/api/v1/projects/#{project.id}/surveys/#{survey.id}/respondents/results?_format=csv"

      response = get conn, project_survey_links_path(conn, :create_link, project, survey, "results")

      assert json_response(response, 200) == %{
        "name" => "survey/#{survey.id}/results",
        "url" => "#{Ask.Endpoint.url}/link/#{link.hash}"
      }
      assert ShortLink |> Repo.all |> length == 1

      response = put conn, project_survey_links_path(conn, :refresh_link, project, survey, "results")

      new_link = ShortLink |> Repo.one

      assert json_response(response, 200) == %{
        "name" => "survey/#{survey.id}/results",
        "url" => "#{Ask.Endpoint.url}/link/#{new_link.hash}"
      }

      assert link.hash != new_link.hash
      assert link.target == new_link.target

      response = delete conn, project_survey_links_path(conn, :delete_link, project, survey, "results")

      assert response(response, 204)
      assert [] == ShortLink |> Repo.all()
    end

    test "incentives link generation", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)

      response = get conn, project_survey_links_path(conn, :create_link, project, survey, "incentives")

      link = ShortLink |> Repo.one

      assert json_response(response, 200) == %{
        "name" => "survey/#{survey.id}/incentives",
        "url" => "#{Ask.Endpoint.url}/link/#{link.hash}"
      }

      response = get conn, project_survey_links_path(conn, :create_link, project, survey, "incentives")

      assert json_response(response, 200) == %{
        "name" => "survey/#{survey.id}/incentives",
        "url" => "#{Ask.Endpoint.url}/link/#{link.hash}"
      }
      assert ShortLink |> Repo.all |> length == 1

      assert link.target == "/api/v1/projects/#{project.id}/surveys/#{survey.id}/respondents/incentives?_format=csv"

      response = put conn, project_survey_links_path(conn, :refresh_link, project, survey, "incentives")

      new_link = ShortLink |> Repo.one

      assert json_response(response, 200) == %{
        "name" => "survey/#{survey.id}/incentives",
        "url" => "#{Ask.Endpoint.url}/link/#{new_link.hash}"
      }

      assert link.hash != new_link.hash
      assert link.target == new_link.target

      response = delete conn, project_survey_links_path(conn, :delete_link, project, survey, "incentives")

      assert response(response, 204)
      assert [] == ShortLink |> Repo.all()
    end

    test "interactions link generation", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)

      response = get conn, project_survey_links_path(conn, :create_link, project, survey, "interactions")

      link = ShortLink |> Repo.one

      assert json_response(response, 200) == %{
        "name" => "survey/#{survey.id}/interactions",
        "url" => "#{Ask.Endpoint.url}/link/#{link.hash}"
      }

      response = get conn, project_survey_links_path(conn, :create_link, project, survey, "interactions")

      assert json_response(response, 200) == %{
        "name" => "survey/#{survey.id}/interactions",
        "url" => "#{Ask.Endpoint.url}/link/#{link.hash}"
      }
      assert ShortLink |> Repo.all |> length == 1

      assert link.target == "/api/v1/projects/#{project.id}/surveys/#{survey.id}/respondents/interactions?_format=csv"

      response = put conn, project_survey_links_path(conn, :refresh_link, project, survey, "interactions")

      new_link = ShortLink |> Repo.one

      assert json_response(response, 200) == %{
        "name" => "survey/#{survey.id}/interactions",
        "url" => "#{Ask.Endpoint.url}/link/#{new_link.hash}"
      }

      assert link.hash != new_link.hash
      assert link.target == new_link.target

      response = delete conn, project_survey_links_path(conn, :delete_link, project, survey, "interactions")

      assert response(response, 204)
      assert [] == ShortLink |> Repo.all()
    end

    test "disposition_history link generation", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)

      response = get conn, project_survey_links_path(conn, :create_link, project, survey, "disposition_history")

      link = ShortLink |> Repo.one

      assert json_response(response, 200) == %{
        "name" => "survey/#{survey.id}/disposition_history",
        "url" => "#{Ask.Endpoint.url}/link/#{link.hash}"
      }
      assert link.target == "/api/v1/projects/#{project.id}/surveys/#{survey.id}/respondents/disposition_history?_format=csv"

      response = get conn, project_survey_links_path(conn, :create_link, project, survey, "disposition_history")

      assert json_response(response, 200) == %{
        "name" => "survey/#{survey.id}/disposition_history",
        "url" => "#{Ask.Endpoint.url}/link/#{link.hash}"
      }
      assert ShortLink |> Repo.all |> length == 1

      response = put conn, project_survey_links_path(conn, :refresh_link, project, survey, "disposition_history")

      new_link = ShortLink |> Repo.one

      assert json_response(response, 200) == %{
        "name" => "survey/#{survey.id}/disposition_history",
        "url" => "#{Ask.Endpoint.url}/link/#{new_link.hash}"
      }

      assert link.hash != new_link.hash
      assert link.target == new_link.target

      response = delete conn, project_survey_links_path(conn, :delete_link, project, survey, "disposition_history")

      assert response(response, 204)
      assert [] == ShortLink |> Repo.all()
    end

    test "forbids readers to create links", %{conn: conn, user: user} do
      project = create_project_for_user(user, level: "reader")
      survey = insert(:survey, project: project)

      assert_error_sent :forbidden, fn ->
        get conn, project_survey_links_path(conn, :create_link, project, survey, "results")
      end
      assert_error_sent :forbidden, fn ->
        get conn, project_survey_links_path(conn, :create_link, project, survey, "incentives")
      end
      assert_error_sent :forbidden, fn ->
        get conn, project_survey_links_path(conn, :create_link, project, survey, "interactions")
      end
      assert_error_sent :forbidden, fn ->
        get conn, project_survey_links_path(conn, :create_link, project, survey, "disposition_history")
      end
    end

    test "forbids readers to refresh links", %{conn: conn, user: user} do
      project = create_project_for_user(user, level: "reader")
      survey = insert(:survey, project: project)

      assert_error_sent :forbidden, fn ->
        put conn, project_survey_links_path(conn, :refresh_link, project, survey, "results")
      end
      assert_error_sent :forbidden, fn ->
        put conn, project_survey_links_path(conn, :refresh_link, project, survey, "incentives")
      end
      assert_error_sent :forbidden, fn ->
        put conn, project_survey_links_path(conn, :refresh_link, project, survey, "interactions")
      end
      assert_error_sent :forbidden, fn ->
        put conn, project_survey_links_path(conn, :refresh_link, project, survey, "disposition_history")
      end
    end

    test "forbids readers to delete links", %{conn: conn, user: user} do
      project = create_project_for_user(user, level: "reader")
      survey = insert(:survey, project: project)

      assert_error_sent :forbidden, fn ->
        delete conn, project_survey_links_path(conn, :delete_link, project, survey, "results")
      end
      assert_error_sent :forbidden, fn ->
        delete conn, project_survey_links_path(conn, :delete_link, project, survey, "incentives")
      end
      assert_error_sent :forbidden, fn ->
        delete conn, project_survey_links_path(conn, :delete_link, project, survey, "interactions")
      end
      assert_error_sent :forbidden, fn ->
        delete conn, project_survey_links_path(conn, :delete_link, project, survey, "disposition_history")
      end
    end

    test "forbids to create links if project is archived", %{conn: conn, user: user} do
      project = create_project_for_user(user, archived: true)
      survey = insert(:survey, project: project)

      assert_error_sent :forbidden, fn ->
        get conn, project_survey_links_path(conn, :create_link, project, survey, "results")
      end
      assert_error_sent :forbidden, fn ->
        get conn, project_survey_links_path(conn, :create_link, project, survey, "incentives")
      end
      assert_error_sent :forbidden, fn ->
        get conn, project_survey_links_path(conn, :create_link, project, survey, "interactions")
      end
      assert_error_sent :forbidden, fn ->
        get conn, project_survey_links_path(conn, :create_link, project, survey, "disposition_history")
      end
    end

    test "forbids to refresh links if project is archived", %{conn: conn, user: user} do
      project = create_project_for_user(user, archived: true)
      survey = insert(:survey, project: project)

      assert_error_sent :forbidden, fn ->
        put conn, project_survey_links_path(conn, :refresh_link, project, survey, "results")
      end
      assert_error_sent :forbidden, fn ->
        put conn, project_survey_links_path(conn, :refresh_link, project, survey, "incentives")
      end
      assert_error_sent :forbidden, fn ->
        put conn, project_survey_links_path(conn, :refresh_link, project, survey, "interactions")
      end
      assert_error_sent :forbidden, fn ->
        put conn, project_survey_links_path(conn, :refresh_link, project, survey, "disposition_history")
      end
    end

    test "forbids to delete links if project is archived", %{conn: conn, user: user} do
      project = create_project_for_user(user, archived: true)
      survey = insert(:survey, project: project)

      assert_error_sent :forbidden, fn ->
        delete conn, project_survey_links_path(conn, :delete_link, project, survey, "results")
      end
      assert_error_sent :forbidden, fn ->
        delete conn, project_survey_links_path(conn, :delete_link, project, survey, "incentives")
      end
      assert_error_sent :forbidden, fn ->
        delete conn, project_survey_links_path(conn, :delete_link, project, survey, "interactions")
      end
      assert_error_sent :forbidden, fn ->
        delete conn, project_survey_links_path(conn, :delete_link, project, survey, "disposition_history")
      end
    end

    test "allows editors to create some links", %{conn: conn, user: user} do
      project = create_project_for_user(user, level: "editor")
      survey = insert(:survey, project: project)

      response = get conn, project_survey_links_path(conn, :create_link, project, survey, "results")
      assert response(response, 200)

      response = get conn, project_survey_links_path(conn, :create_link, project, survey, "disposition_history")
      assert response(response, 200)

      assert_error_sent :forbidden, fn ->
        get conn, project_survey_links_path(conn, :create_link, project, survey, "incentives")
      end

      assert_error_sent :forbidden, fn ->
        get conn, project_survey_links_path(conn, :create_link, project, survey, "interactions")
      end
    end

    test "allows editors to refresh some links", %{conn: conn, user: user} do
      project = create_project_for_user(user, level: "editor")
      survey = insert(:survey, project: project)
      get conn, project_survey_links_path(conn, :create_link, project, survey, "results")
      get conn, project_survey_links_path(conn, :create_link, project, survey, "disposition_history")

      response = put conn, project_survey_links_path(conn, :refresh_link, project, survey, "results")
      assert response(response, 200)

      response = put conn, project_survey_links_path(conn, :refresh_link, project, survey, "disposition_history")
      assert response(response, 200)

      assert_error_sent :forbidden, fn ->
        put conn, project_survey_links_path(conn, :refresh_link, project, survey, "incentives")
      end
      assert_error_sent :forbidden, fn ->
        put conn, project_survey_links_path(conn, :refresh_link, project, survey, "interactions")
      end
    end

    test "forbids editor to delete some links", %{conn: conn, user: user} do
      project = create_project_for_user(user, level: "editor")
      survey = insert(:survey, project: project)
      get conn, project_survey_links_path(conn, :create_link, project, survey, "results")
      get conn, project_survey_links_path(conn, :create_link, project, survey, "disposition_history")

      response = delete conn, project_survey_links_path(conn, :delete_link, project, survey, "results")
      assert response(response, 204)

      response = delete conn, project_survey_links_path(conn, :delete_link, project, survey, "disposition_history")
      assert response(response, 204)

      assert_error_sent :forbidden, fn ->
        delete conn, project_survey_links_path(conn, :delete_link, project, survey, "incentives")
      end
      assert_error_sent :forbidden, fn ->
        delete conn, project_survey_links_path(conn, :delete_link, project, survey, "interactions")
      end
    end
  end

  describe "activity logs" do
    setup %{conn: conn} do
      remote_ip = {192, 168, 0, 128}
      conn = %{conn | remote_ip: remote_ip}
      {:ok, conn: conn, remote_ip: remote_ip}
    end

    test "generates logs for results link", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)

      get conn, project_survey_links_path(conn, :create_link, project, survey, "results")
      activity_log_create = ActivityLog |> where([log], log.action == "enable_public_link") |> Repo.one
      assert_link_log(%{log: activity_log_create, user: user, project: project, survey: survey, action: "enable_public_link", report_type: "survey_results", remote_ip: "192.168.0.128"})

      put conn, project_survey_links_path(conn, :refresh_link, project, survey, "results")
      activity_log_regenerate = ActivityLog |> where([log], log.action == "regenerate_public_link") |> Repo.one
      assert_link_log(%{log: activity_log_regenerate, user: user, project: project, survey: survey, action: "regenerate_public_link", report_type: "survey_results", remote_ip: "192.168.0.128"})

      delete conn, project_survey_links_path(conn, :delete_link, project, survey, "results")
      activity_log_delete = ActivityLog |> where([log], log.action == "disable_public_link") |> Repo.one
      assert_link_log(%{log: activity_log_delete, user: user, project: project, survey: survey, action: "disable_public_link", report_type: "survey_results", remote_ip: "192.168.0.128"})
    end

    test "generates logs for incentives link", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)

      get conn, project_survey_links_path(conn, :create_link, project, survey, "incentives")
      activity_log_create = ActivityLog |> where([log], log.action == "enable_public_link") |> Repo.one
      assert_link_log(%{log: activity_log_create, user: user, project: project, survey: survey, action: "enable_public_link", report_type: "incentives", remote_ip: "192.168.0.128"})

      put conn, project_survey_links_path(conn, :refresh_link, project, survey, "incentives")
      activity_log_regenerate = ActivityLog |> where([log], log.action == "regenerate_public_link") |> Repo.one
      assert_link_log(%{log: activity_log_regenerate, user: user, project: project, survey: survey, action: "regenerate_public_link", report_type: "incentives", remote_ip: "192.168.0.128"})

      delete conn, project_survey_links_path(conn, :delete_link, project, survey, "incentives")
      activity_log_delete = ActivityLog |> where([log], log.action == "disable_public_link") |> Repo.one
      assert_link_log(%{log: activity_log_delete, user: user, project: project, survey: survey, action: "disable_public_link", report_type: "incentives", remote_ip: "192.168.0.128"})
    end

    test "generates logs for interactions link", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)

      get conn, project_survey_links_path(conn, :create_link, project, survey, "interactions")
      activity_log_create = ActivityLog |> where([log], log.action == "enable_public_link") |> Repo.one
      assert_link_log(%{log: activity_log_create, user: user, project: project, survey: survey, action: "enable_public_link", report_type: "interactions", remote_ip: "192.168.0.128"})

      put conn, project_survey_links_path(conn, :refresh_link, project, survey, "interactions")
      activity_log_regenerate = ActivityLog |> where([log], log.action == "regenerate_public_link") |> Repo.one
      assert_link_log(%{log: activity_log_regenerate, user: user, project: project, survey: survey, action: "regenerate_public_link", report_type: "interactions", remote_ip: "192.168.0.128"})

      delete conn, project_survey_links_path(conn, :delete_link, project, survey, "interactions")
      activity_log_delete = ActivityLog |> where([log], log.action == "disable_public_link") |> Repo.one
      assert_link_log(%{log: activity_log_delete, user: user, project: project, survey: survey, action: "disable_public_link", report_type: "interactions", remote_ip: "192.168.0.128"})
    end

    test "generates logs for disposition_history link", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)

      get conn, project_survey_links_path(conn, :create_link, project, survey, "disposition_history")
      activity_log_create = ActivityLog |> where([log], log.action == "enable_public_link") |> Repo.one
      assert_link_log(%{log: activity_log_create, user: user, project: project, survey: survey, action: "enable_public_link", report_type: "disposition_history", remote_ip: "192.168.0.128"})

      put conn, project_survey_links_path(conn, :refresh_link, project, survey, "disposition_history")
      activity_log_regenerate = ActivityLog |> where([log], log.action == "regenerate_public_link") |> Repo.one
      assert_link_log(%{log: activity_log_regenerate, user: user, project: project, survey: survey, action: "regenerate_public_link", report_type: "disposition_history", remote_ip: "192.168.0.128"})

      delete conn, project_survey_links_path(conn, :delete_link, project, survey, "disposition_history")
      activity_log_delete = ActivityLog |> where([log], log.action == "disable_public_link") |> Repo.one
      assert_link_log(%{log: activity_log_delete, user: user, project: project, survey: survey, action: "disable_public_link", report_type: "disposition_history", remote_ip: "192.168.0.128"})
    end

    test "generates log after creating a survey", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      post conn, project_survey_path(conn, :create, project.id)

      log = ActivityLog |> Repo.one
      survey = Survey |> Repo.one

      assert_survey_log(%{log: log, user: user, project: project, survey: survey, action: "create", remote_ip: "192.168.0.128", metadata: nil})
    end

    test "generates log after deleting a survey", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)

      delete conn, project_survey_path(conn, :delete, survey.project, survey)
      log = ActivityLog |> Repo.one

      assert_survey_log(%{log: log, user: user, project: project, survey: survey, action: "delete", remote_ip: "192.168.0.128", metadata: %{"survey_name" => survey.name}})
    end

    test "generates log after launching a survey", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project, state: "ready")

      post conn, project_survey_survey_path(conn, :launch, survey.project, survey)
      log = ActivityLog |> Repo.one

      assert_survey_log(%{log: log, user: user, project: project, survey: survey, action: "start", remote_ip: "192.168.0.128", metadata: %{"survey_name" => survey.name}})
    end

    test "generates log after stopping a survey", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project, state: "running")

      post conn, project_survey_survey_path(conn, :stop, survey.project, survey)
      log = ActivityLog|> Repo.one

      assert_survey_log(%{log: log, user: user, project: project, survey: survey, action: "stop", remote_ip: "192.168.0.128", metadata: %{"survey_name" => survey.name}})
    end

    test "generates log after updating a survey", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)

      put conn, project_survey_path(conn, :update, project, survey), survey: %{cutoff: 30}
      log = ActivityLog|> Repo.one

      assert_survey_log(%{log: log, user: user, project: project, survey: survey, action: "edit", remote_ip: "192.168.0.128", metadata: %{"survey_name" => survey.name}})
    end

    test "generates rename log if name changed", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)

      put conn, project_survey_path(conn, :update, project, survey), survey: %{name: "new name", quotas: %{vars: [], buckets: []}, questionnaires: []}
      log = ActivityLog|> Repo.one

      assert_survey_log(%{log: log, user: user, project: project, survey: survey, action: "rename", remote_ip: "192.168.0.128", metadata: %{"old_survey_name" => survey.name, "new_survey_name" => "new name"}})
    end

    test "generates both rename and edit log if name and another property changes", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)

      put conn, project_survey_path(conn, :update, project, survey), survey: %{cutoff: 30, name: "new name"}
      rename_log = ActivityLog|> where([log], log.action == "rename") |> Repo.one
      edit_log = ActivityLog|> where([log], log.action == "edit") |> Repo.one

      assert_survey_log(%{log: rename_log, user: user, project: project, survey: survey, action: "rename", remote_ip: "192.168.0.128", metadata: %{"old_survey_name" => survey.name, "new_survey_name" => "new name"}})
      assert_survey_log(%{log: edit_log, user: user, project: project, survey: survey, action: "edit", remote_ip: "192.168.0.128", metadata: %{"survey_name" => survey.name}})
    end

    test "generates rename log with set_name action", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      survey = insert(:survey, project: project)

      post conn, project_survey_survey_path(conn, :set_name, project, survey), name: "new name"
      log = ActivityLog |> Repo.one!()

      assert_survey_log(%{log: log, user: user, project: project, survey: survey, action: "rename", remote_ip: "192.168.0.128", metadata: %{"old_survey_name" => survey.name, "new_survey_name" => "new name"}})
    end
  end

  def prepare_for_state_update(user) do
    project = create_project_for_user(user)
    questionnaire = insert(:questionnaire, name: "test", project: project)
    channel = insert(:channel, name: "test")
    [project, questionnaire, channel]
  end

  defp add_respondent_to(group = %RespondentGroup{}) do
    insert(:respondent, phone_number: "12345678", survey: group.survey, respondent_group: group)
  end

  def completed_schedule() do
    Ask.Schedule.always()
  end

  def incomplete_schedule() do
    Ask.Schedule.default
  end

  defp add_channel_to(group = %RespondentGroup{}, channel = %Channel{}) do
    RespondentGroupChannel.changeset(%RespondentGroupChannel{}, %{respondent_group_id: group.id, channel_id: channel.id, mode: channel.type})
    |> Repo.insert
  end

  defp create_group(survey, channel \\ nil) do
    group = insert(:respondent_group, survey: survey, respondents_count: 1)
    if channel do
      add_channel_to(group, channel)
    end
    add_respondent_to group
    group
  end

  defp assert_log(log, user, project, survey, action, remote_ip) do
    assert log.project_id == project.id
    assert log.user_id == user.id
    assert log.entity_id == survey.id
    assert log.entity_type == "survey"
    assert log.action == action
    assert log.remote_ip == remote_ip
  end

  defp assert_link_log(%{log: log, user: user, project: project, survey: survey, action: action, report_type: report_type, remote_ip: remote_ip}) do
    assert_log(log, user, project, survey, action, remote_ip)
    assert log.metadata == %{
      "survey_name" => survey.name,
      "report_type" => report_type
    }
  end

  defp assert_survey_log(%{log: log, user: user, project: project, survey: survey, action: action, remote_ip: remote_ip, metadata: metadata}) do
    assert_log(log, user, project, survey, action, remote_ip)
    assert log.metadata == metadata
  end
end
