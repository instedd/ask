defmodule Ask.QuestionnaireControllerTest do
  use Ask.ConnCase
  use Ask.DummySteps
  use Ask.TestHelpers
  import Ask.StepBuilder

  alias Ask.{Project, Questionnaire, Translation, JsonSchema}
  @valid_attrs %{name: "some content", modes: ["sms", "ivr"], steps: []}
  @invalid_attrs %{steps: []}

  setup %{conn: conn} do
    GenServer.start_link(JsonSchema, [], name: JsonSchema.server_ref)

    user = insert(:user)
    conn = conn
      |> put_private(:test_user, user)
      |> put_req_header("accept", "application/json")
    {:ok, conn: conn, user: user}
  end

  describe "login" do
    test "denies access without login token" do
      conn = build_conn()
      conn = get conn, project_questionnaire_path(conn, :index, -1)
      assert json_response(conn, :unauthorized)["error"] == "Unauthorized"
    end

    test "user is deleted from session if the user does not exist" do
      user = build(:user, id: -1)
      conn = build_conn()
      |> put_private(:test_user, user)
      |> put_req_header("accept", "application/json")
      conn = get conn, project_questionnaire_path(conn, :index, user)
      assert json_response(conn, :unauthorized)["error"] == "Unauthorized"
    end
  end

  describe "index:" do
    test "returns 404 when the project does not exist", %{conn: conn} do
      assert_error_sent 404, fn ->
        get conn, project_questionnaire_path(conn, :index, -1)
      end
    end

    test "returns code 200 and empty list if there are no entries", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      conn = get conn, project_questionnaire_path(conn, :index, project.id)
      assert json_response(conn, 200)["data"] == []
    end

    test "forbid index access if the project does not belong to the current user", %{conn: conn} do
      questionnaire = insert(:questionnaire)
      assert_error_sent :forbidden, fn ->
        get conn, project_questionnaire_path(conn, :index, questionnaire.project)
      end
    end
  end

  describe "show:" do
    test "renders chosen resource", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      questionnaire = insert(:questionnaire, project: project)
      conn = get conn, project_questionnaire_path(conn, :show, questionnaire.project, questionnaire)
      assert json_response(conn, 200)["data"] == %{"id" => questionnaire.id,
        "name" => questionnaire.name,
        "project_id" => questionnaire.project_id,
        "modes" => ["sms", "ivr"],
        "steps" => [],
        "default_language" => "en",
        "languages" => [],
        "updated_at" => Ecto.DateTime.to_iso8601(questionnaire.updated_at),
        "mobile_web_sms_message" => nil,
        "quota_completed_msg" => %{
          "en" => %{
            "sms" => "Quota completed",
            "ivr" => %{
              "audio_source" => "tts",
              "text" => "Quota completed (ivr)"
            }
          }
        },
        "error_msg" => %{
          "en" => %{
            "sms" => "You have entered an invalid answer",
            "ivr" => %{
              "audio_source" => "tts",
              "text" => "You have entered an invalid answer (ivr)"
            }
          }
        },
        "mobile_web_sms_message" => "Please enter",
        "valid" => true
      }
    end

    test "renders page not found when id is nonexistent", %{conn: conn} do
      assert_error_sent 404, fn ->
        get conn, project_questionnaire_path(conn, :show, -1, -1)
      end
    end

    test "forbid access to questionnaire if the project does not belong to the current user", %{conn: conn} do
      questionnaire = insert(:questionnaire)
      assert_error_sent :forbidden, fn ->
        get conn, project_questionnaire_path(conn, :show, questionnaire.project, questionnaire)
      end
    end
  end

  describe "create:" do
    test "creates and renders resource when data is valid", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      conn = post conn, project_questionnaire_path(conn, :create, project.id), questionnaire: @valid_attrs
      assert json_response(conn, 201)["data"]["id"]
      assert Repo.get_by(Questionnaire, @valid_attrs)
    end

    test "creates with default languages and default_language", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      conn = post conn, project_questionnaire_path(conn, :create, project.id), questionnaire: @valid_attrs
      questionnaire = Questionnaire |> Ask.Repo.get(json_response(conn, 201)["data"]["id"])
      assert questionnaire.languages == ["en"]
      assert questionnaire.default_language == "en"
    end

    test "does not create resource and renders errors when data is invalid", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      conn = post conn, project_questionnaire_path(conn, :create, project.id), questionnaire: @invalid_attrs
      assert json_response(conn, 422)["errors"] != %{}
    end

    test "forbids creation of questionnaire for a project that belongs to another user", %{conn: conn} do
      project = insert(:project)
      assert_error_sent :forbidden, fn ->
        post conn, project_questionnaire_path(conn, :create, project.id), questionnaire: @valid_attrs
      end
    end

    test "forbids creation of questionnaire for a project reader", %{conn: conn, user: user} do
      project = create_project_for_user(user, level: "reader")
      assert_error_sent :forbidden, fn ->
        post conn, project_questionnaire_path(conn, :create, project.id), questionnaire: @valid_attrs
      end
    end

    test "updates project updated_at when questionnaire is created", %{conn: conn, user: user}  do
      datetime = Ecto.DateTime.cast!("2000-01-01 00:00:00")
      project = insert(:project, updated_at: datetime)
      insert(:project_membership, user: user, project: project, level: "owner")
      post conn, project_questionnaire_path(conn, :create, project.id), questionnaire: @valid_attrs

      project = Project |> Repo.get(project.id)
      assert Ecto.DateTime.compare(project.updated_at, datetime) == :gt
    end

    test "creates and recreates variables", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      questionnaire = %{name: "some content", modes: ["sms", "ivr"], steps: @dummy_steps}

      original_conn = conn

      conn = post original_conn, project_questionnaire_path(conn, :create, project.id), questionnaire: questionnaire
      id = json_response(conn, 201)["data"]["id"]
      assert id

      vars = (Questionnaire
      |> Repo.get!(id)
      |> Repo.preload(:questionnaire_variables)).questionnaire_variables
      assert length(vars) == 4

      steps = [
        multiple_choice_step(
          id: "aaa",
          title: "Title",
          prompt: %{
          },
          store: "Swims",
          choices: []
        )
      ]
      questionnaire = Questionnaire |> Repo.get!(id)

      conn = put original_conn, project_questionnaire_path(original_conn, :update, project, questionnaire), questionnaire: %{steps: steps}
      id = json_response(conn, 200)["data"]["id"]
      assert id

      vars = (Questionnaire
      |> Repo.get!(id)
      |> Repo.preload(:questionnaire_variables)).questionnaire_variables
      assert length(vars) == 1
    end
  end

  describe "update:" do
    test "updates and renders chosen resource when data is valid", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      questionnaire = insert(:questionnaire, project: project)
      conn = put conn, project_questionnaire_path(conn, :update, project, questionnaire), questionnaire: @valid_attrs
      assert json_response(conn, 200)["data"]["id"]
      assert Repo.get_by(Questionnaire, @valid_attrs)
    end

    test "rejects update if the questionnaire doesn't belong to the current user", %{conn: conn} do
      questionnaire = insert(:questionnaire)
      assert_error_sent :forbidden, fn ->
        put conn, project_questionnaire_path(conn, :update, questionnaire.project, questionnaire), questionnaire: @invalid_attrs
      end
    end

    test "rejects update for a project reader", %{conn: conn, user: user} do
      project = create_project_for_user(user, level: "reader")
      questionnaire = insert(:questionnaire, project: project)
      assert_error_sent :forbidden, fn ->
        put conn, project_questionnaire_path(conn, :update, questionnaire.project, questionnaire), questionnaire: @invalid_attrs
      end
    end

    test "updates project updated_at when questionnaire is updated", %{conn: conn, user: user}  do
      datetime = Ecto.DateTime.cast!("2000-01-01 00:00:00")
      project = create_project_for_user(user)
      questionnaire = insert(:questionnaire, project: project)
      put conn, project_questionnaire_path(conn, :update, project, questionnaire), questionnaire: @valid_attrs

      project = Project |> Repo.get(project.id)
      assert Ecto.DateTime.compare(project.updated_at, datetime) == :gt
    end

    test "updates and creates variables", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      questionnaire = insert(:questionnaire, project: project)

      %Ask.QuestionnaireVariable{
        project_id: questionnaire.project_id,
        questionnaire_id: questionnaire.id,
        name: "Gonna be erased",
      } |> Repo.insert!

      conn = put conn, project_questionnaire_path(conn, :update, project, questionnaire), questionnaire: %{steps: @dummy_steps}
      assert json_response(conn, 200)["data"]["id"]

      vars = (Questionnaire
      |> Repo.get!(questionnaire.id)
      |> Repo.preload(:questionnaire_variables)).questionnaire_variables
      assert length(vars) == 4
    end

    test "updates survey ready state when valid changes", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      questionnaire = insert(:questionnaire, project: project, valid: true)
      survey = insert(:survey, project: project, questionnaires: [questionnaire], state: "ready")

      put conn, project_questionnaire_path(conn, :update, project, questionnaire), questionnaire: %{"valid" => false, steps: []}

      survey = Ask.Survey |> Repo.get!(survey.id)
      assert survey.state == "not_ready"
    end

    test "updates survey ready state when mode changes", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      questionnaire = insert(:questionnaire, project: project)
      survey = insert(:survey, project: project, questionnaires: [questionnaire], state: "ready")

      put conn, project_questionnaire_path(conn, :update, project, questionnaire), questionnaire: %{"modes" => ["ivr"], steps: []}

      survey = Ask.Survey |> Repo.get!(survey.id)
      assert survey.state == "not_ready"
    end
  end

  describe "update translations" do
    test "creates no translations", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      questionnaire = insert(:questionnaire, project: project, quota_completed_msg: nil, error_msg: nil)

      steps = []
      put conn, project_questionnaire_path(conn, :update, project, questionnaire), questionnaire: %{steps: steps}

      assert (Translation |> Repo.all |> length) == 0
    end

    test "creates translations for one sms prompt", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      questionnaire = insert(:questionnaire, project: project, quota_completed_msg: nil, error_msg: nil)

      steps = [
        multiple_choice_step(
          id: "aaa",
          title: "Title",
          prompt: %{
            "en" => %{"sms" => "EN 1"},
            "es" => %{"sms" => "ES 1"},
          },
          store: "X",
          choices: []
        )
      ]
      conn = put conn, project_questionnaire_path(conn, :update, project, questionnaire), questionnaire: %{steps: steps}
      assert json_response(conn, 200)["data"]["id"]

      translations = Translation |> Repo.all
      assert (translations |> length) == 1

      t = hd(translations)
      assert t.project_id == project.id
      assert t.questionnaire_id == questionnaire.id
      assert t.mode == "sms"
      assert t.source_lang == "en"
      assert t.source_text == "EN 1"
      assert t.target_lang == "es"
      assert t.target_text == "ES 1"
    end

    test "creates translations when no translation", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      questionnaire = insert(:questionnaire, project: project, quota_completed_msg: nil, error_msg: nil)

      steps = [
        multiple_choice_step(
          id: "aaa",
          title: "Title",
          prompt: %{
            "en" => %{"sms" => "EN 1"},
          },
          store: "X",
          choices: []
        )
      ]
      conn = put conn, project_questionnaire_path(conn, :update, project, questionnaire), questionnaire: %{steps: steps}
      assert json_response(conn, 200)["data"]["id"]

      translations = Translation |> Repo.all
      assert (translations |> length) == 1

      t = hd(translations)
      assert t.project_id == project.id
      assert t.questionnaire_id == questionnaire.id
      assert t.mode == "sms"
      assert t.source_lang == "en"
      assert t.source_text == "EN 1"
      assert t.target_lang == nil
      assert t.target_text == nil
    end

    test "creates and recreates translations for other pieces", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      questionnaire = insert(:questionnaire, project: project, quota_completed_msg: nil, error_msg: nil)

      # Multiple additions

      steps = [
        multiple_choice_step(
          id: "aaa",
          title: "Title",
          prompt: %{
            "en" => %{"sms" => "EN 1", "ivr" => %{"text" => "EN 2", "audio_source": "tts"}},
            "es" => %{"sms" => "ES 1"},
            "fr" => %{"sms" => "", "ivr" => %{"text" => "FR 2", "audio_source": "tts"}},
          },
          store: "X",
          choices: [
            choice(value: "", responses: %{
              "sms" => %{
                "en" => ["EN 3", "EN 4"],
                "es" => ["ES 3", "ES 4"],
                "fr" => [""],
              },
            })
          ]
        )
      ]
      quota_completed_msg = %{
        "en" => %{"sms" => "EN 5", "ivr" => %{"text" => "EN 6", "audio_source": "tts"}},
        "es" => %{"sms" => "ES 5"},
        "fr" => %{"sms" => "", "ivr" => %{"text" => "FR 6", "audio_source": "tts"}},
      }

      original_conn = conn

      conn = put conn, project_questionnaire_path(conn, :update, project, questionnaire),
      questionnaire: %{steps: steps, quota_completed_msg: quota_completed_msg}
      assert json_response(conn, 200)["data"]["id"]

      translations = Translation
      |> Repo.all
      |> Enum.map(&{&1.mode, &1.scope, &1.source_lang, &1.source_text, &1.target_lang, &1.target_text})
      |> Enum.sort

      expected = [
        {"sms", "prompt", "en", "EN 1", "es", "ES 1"},
        {"ivr", "prompt", "en", "EN 2", "fr", "FR 2"},
        {"sms", "response", "en", "EN 3, EN 4", "es", "ES 3, ES 4"},
        {"sms", "quota_completed", "en", "EN 5", "es", "ES 5"},
        {"ivr", "quota_completed", "en", "EN 6", "fr", "FR 6"},
      ] |> Enum.sort

      assert translations == expected

      # Additions and deletions

      steps = [
        multiple_choice_step(
          id: "aaa",
          title: "Title",
          prompt: %{
            "en" => %{"sms" => "EN 1", "ivr" => %{"text" => "EN 2", "audio_source": "tts"}},
            "es" => %{"sms" => ""},
            "fr" => %{"sms" => "", "ivr" => %{"text" => "FR 2 (NEW)", "audio_source": "tts"}},
          },
          store: "X",
          choices: [
            choice(value: "", responses: %{
              "sms" => %{
                "en" => ["EN 3", "EN 4"],
                "es" => ["ES 3", "ES 4"],
                "fr" => ["FR 3", "FR 4"],
              },
            }),
            choice(value: "", responses: %{
              "sms" => %{
                "en" => ["EN 3", "EN 4"],
                "es" => ["ES 10"],
                "fr" => ["FR 3", "FR 4"],
              },
            })
          ]
        )
      ]

      conn = put original_conn, project_questionnaire_path(conn, :update, project, questionnaire),
      questionnaire: %{steps: steps, quota_completed_msg: quota_completed_msg}
      assert json_response(conn, 200)["data"]["id"]

      translations = Translation
      |> Repo.all
      |> Enum.map(&{&1.mode, &1.scope, &1.source_lang, &1.source_text, &1.target_lang, &1.target_text})
      |> Enum.sort

      expected = [
        {"sms", "prompt", "en", "EN 1", nil, nil},
        {"ivr", "prompt", "en", "EN 2", "fr", "FR 2 (NEW)"},
        {"sms", "response", "en", "EN 3, EN 4", "es", "ES 10"},
        {"sms", "response", "en", "EN 3, EN 4", "es", "ES 3, ES 4"},
        {"sms", "response", "en", "EN 3, EN 4", "fr", "FR 3, FR 4"},
        {"sms", "quota_completed", "en", "EN 5", "es", "ES 5"},
        {"ivr", "quota_completed", "en", "EN 6", "fr", "FR 6"},
      ] |> Enum.sort

      assert translations == expected

      # Single change (optimization)

      steps = [
        multiple_choice_step(
          id: "aaa",
          title: "Title",
          prompt: %{
            "en" => %{"sms" => "EN 1", "ivr" => %{"text" => "EN 2", "audio_source": "tts"}},
            "es" => %{"sms" => ""},
            "fr" => %{"sms" => "", "ivr" => %{"text" => "FR 2 (NEW)", "audio_source": "tts"}},
          },
          store: "X",
          choices: [
            choice(value: "", responses: %{
              "sms" => %{
                "en" => ["EN 3", "EN 4"],
                "es" => ["ES 3", "ES 4"],
                "fr" => ["FR 3", "FR 4"],
              },
            }),
            choice(value: "", responses: %{
              "sms" => %{
                "en" => ["EN 3", "EN 4"],
                "es" => ["ES 9"],
                "fr" => ["FR 3", "FR 4"],
              },
            })
          ]
        )
      ]

      conn = put original_conn, project_questionnaire_path(conn, :update, project, questionnaire),
      questionnaire: %{steps: steps, quota_completed_msg: quota_completed_msg}
      assert json_response(conn, 200)["data"]["id"]

      translations = Translation
      |> Repo.all
      |> Enum.map(&{&1.mode, &1.scope, &1.source_lang, &1.source_text, &1.target_lang, &1.target_text})
      |> Enum.sort

      expected = [
        {"sms", "prompt", "en", "EN 1", nil, nil},
        {"ivr", "prompt", "en", "EN 2", "fr", "FR 2 (NEW)"},
        {"sms", "response", "en", "EN 3, EN 4", "es", "ES 9"},
        {"sms", "response", "en", "EN 3, EN 4", "es", "ES 3, ES 4"},
        {"sms", "response", "en", "EN 3, EN 4", "fr", "FR 3, FR 4"},
        {"sms", "quota_completed", "en", "EN 5", "es", "ES 5"},
        {"ivr", "quota_completed", "en", "EN 6", "fr", "FR 6"},
      ] |> Enum.sort

      assert translations == expected
    end
  end

  describe "delete:" do
    test "deletes chosen resource", %{conn: conn, user: user} do
      project = create_project_for_user(user)
      questionnaire = insert(:questionnaire, project: project)
      conn = delete conn, project_questionnaire_path(conn, :delete, project, questionnaire)
      assert response(conn, 204)
      refute Repo.get(Questionnaire, questionnaire.id)
    end

    test "rejects delete if the questionnaire doesn't belong to the current user", %{conn: conn} do
      questionnaire = insert(:questionnaire)
      assert_error_sent :forbidden, fn ->
        delete conn, project_questionnaire_path(conn, :delete, questionnaire.project, questionnaire)
      end
    end

    test "rejects delete for a project reader", %{conn: conn, user: user} do
      project = create_project_for_user(user, level: "reader")
      questionnaire = insert(:questionnaire, project: project)
      assert_error_sent :forbidden, fn ->
        delete conn, project_questionnaire_path(conn, :delete, questionnaire.project, questionnaire)
      end
    end

    test "updates project updated_at when questionnaire is deleted", %{conn: conn, user: user}  do
      datetime = Ecto.DateTime.cast!("2000-01-01 00:00:00")
      project = insert(:project, updated_at: datetime)
      insert(:project_membership, user: user, project: project, level: "owner")
      questionnaire = insert(:questionnaire, project: project)
      delete conn, project_questionnaire_path(conn, :delete, project, questionnaire)

      project = Project |> Repo.get(project.id)
      assert Ecto.DateTime.compare(project.updated_at, datetime) == :gt
    end
  end
end
