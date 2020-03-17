defmodule Ask.Runtime.BrokerTest do
  use Ask.ModelCase
  use Ask.DummySteps
  use Timex
  use Ask.MockTime
  use Ask.TestHelpers

  alias Ask.Runtime.{Broker, ReplyHelper, ChannelStatusServer, SurveyLogger, Flow}
  alias Ask.{Repo, Respondent, Survey, Schedule, RespondentGroupChannel, TestChannel, QuotaBucket, RespondentDispositionHistory}
  alias Ask.Router.Helpers, as: Routes
  require Ask.Runtime.ReplyHelper

  setup do
    {:ok, channel_status_server} = ChannelStatusServer.start_link
    {:ok, channel_status_server: channel_status_server}
  end

  describe "retry respondents" do
    test "SMS mode" do
      [survey, _group, test_channel, _respondent, phone_number] = create_running_survey_with_channel_and_respondent()
      survey |> Survey.changeset(%{sms_retry_configuration: "10m"}) |> Repo.update

      # First poll, activate the respondent
      Broker.handle_info(:poll, nil)
      assert_received [:setup, ^test_channel, respondent = %Respondent{sanitized_phone_number: ^phone_number}, token]
      assert_received [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

      # Set for immediate timeout
      respondent = Repo.get!(Respondent, respondent.id)
      assert respondent.stats.attempts["sms"] == 1
      Respondent.changeset(respondent, %{timeout_at: Timex.now |> Timex.shift(minutes: -1)}) |> Repo.update

      # Second poll, retry the question
      Broker.handle_info(:poll, nil)
      refute_received [:setup, _, _, _, _]
      assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

      # Set for immediate timeout
      respondent = Repo.get!(Respondent, respondent.id)
      Respondent.changeset(respondent, %{timeout_at: Timex.now |> Timex.shift(minutes: -1)}) |> Repo.update

      # Third poll, this time it should stall
      Broker.handle_info(:poll, nil)

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.state == "stalled"

      survey = Repo.get(Survey, survey.id)
      assert survey.state == "running"
    end

    @tag :time_mock
    test "SMS mode with inactivity periods" do
      [survey, _group, test_channel, _respondent, phone_number] = create_running_survey_with_channel_and_respondent(@dummy_steps, "sms", Schedule.business_day(), "3h")
      survey |> Survey.changeset(%{sms_retry_configuration: "2h"}) |> Repo.update

      {:ok, edge_time, _} = DateTime.from_iso8601("2019-12-06T17:00:00Z")
      mock_time(edge_time)

      # First poll, activate the respondent
      Broker.handle_info(:poll, nil)
      assert_received [:setup, ^test_channel, respondent = %Respondent{sanitized_phone_number: ^phone_number}, token]
      assert_received [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

      # Assert activation
      {:ok, expected_timeout_at, _} = DateTime.from_iso8601("2019-12-09T09:00:00Z")

      respondent = Repo.get!(Respondent, respondent.id)
      assert respondent.timeout_at == expected_timeout_at
      assert respondent.stats.attempts["sms"] == 1

      # Set for immediate timeout
      {:ok, timeout_time, _} = DateTime.from_iso8601("2019-12-09T09:00:00Z")
      mock_time(timeout_time)

      # Second poll, retry the question
      Broker.handle_info(:poll, nil)
      refute_received [:setup, _, _, _, _]
      assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

      # Assert first retry
      {:ok, expected_timeout_at, _} = DateTime.from_iso8601("2019-12-09T11:00:00Z")

      respondent = Repo.get!(Respondent, respondent.id)
      assert respondent.timeout_at == expected_timeout_at
      assert respondent.stats.attempts["sms"] == 2

      # Set for immediate timeout
      {:ok, timeout_time, _} = DateTime.from_iso8601("2019-12-09T12:00:00Z")
      mock_time(timeout_time)

      # Third poll, this time it should stall
      Broker.handle_info(:poll, nil)

      # Assert is stalled
      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.state == "stalled"
      assert respondent.stats.attempts["sms"] == 2
      refute respondent.timeout_at
      survey = Repo.get(Survey, survey.id)
      assert survey.state == "running"
    end

    test "mobileweb mode" do
      [survey, _group, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent(@mobileweb_dummy_steps, "mobileweb")
      survey |> Survey.changeset(%{mobileweb_retry_configuration: "10m"}) |> Repo.update
      sequence_mode = ["mobileweb"]

      {:ok, broker} = Broker.start_link
      Broker.poll

      assert_receive [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number, mode: ^sequence_mode}, _, ReplyHelper.simple("Contact", message)]
      assert message == "Please enter #{Routes.mobile_survey_url(Ask.Endpoint, :index, respondent.id, token: Respondent.token(respondent.id))}"

      survey = Repo.get(Survey, survey.id)
      assert survey.state == "running"

      respondent = Repo.get!(Respondent, respondent.id)
      assert respondent.stats.attempts["mobileweb"] == 1
      assert respondent.state == "active"

      # Set for immediate timeout
      timeout_at = Timex.now |> Timex.shift(hours: -1)
      Respondent.changeset(respondent, %{timeout_at: timeout_at}) |> Repo.update

      # Second poll, retry the question
      Broker.poll
      refute_received [:setup, _, _, _, _]
      assert_receive [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _, ReplyHelper.simple("Contact", message)]
      assert message == "Please enter #{Routes.mobile_survey_url(Ask.Endpoint, :index, respondent.id, token: Respondent.token(respondent.id))}"

      respondent = Repo.get!(Respondent, respondent.id)

      # Set for immediate timeout
      timeout_at = Timex.now |> Timex.shift(hours: -1)
      Respondent.changeset(respondent, %{timeout_at: timeout_at}) |> Repo.update

      # Third poll, this time it should stall
      Broker.poll

      respondent = Repo.get(Respondent, respondent.id)

      assert respondent.state == "stalled"
      refute respondent.timeout_at

      survey = Repo.get(Survey, survey.id)
      assert survey.state == "running"

      :ok = broker |> GenServer.stop
    end

    test "IVR mode" do
      [survey, _group, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent(@dummy_steps, "ivr")
      survey |> Survey.changeset(%{ivr_retry_configuration: "10m"}) |> Repo.update
      sequence_mode = ["ivr"]

      # First poll, activate the respondent
      Broker.handle_info(:poll, nil)
      assert_received [:setup, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number, mode: ^sequence_mode}, _token]

      # Set for immediate timeout
      respondent = Repo.get(Respondent, respondent.id)
      Respondent.changeset(respondent, %{timeout_at: Timex.now |> Timex.shift(minutes: -1)}) |> Repo.update

      # Second poll, retry the question
      Broker.handle_info(:poll, nil)
      assert_received [:setup, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token]

      # Set for immediate timeout
      respondent = Repo.get(Respondent, respondent.id)
      Respondent.changeset(respondent, %{timeout_at: Timex.now |> Timex.shift(minutes: -1)}) |> Repo.update

      # Third poll, this time it should fail
      Broker.handle_info(:poll, nil)

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.state == "failed"

      survey = Repo.get(Survey, survey.id)
      assert Survey.completed?(survey)
    end
  end

  describe "fallback respondent" do
    test "fallback respondent (SMS => IVR)" do
      test_channel = TestChannel.new
      channel = insert(:channel, settings: test_channel |> TestChannel.settings, type: "sms")

      test_fallback_channel = TestChannel.new
      fallback_channel = insert(:channel, settings: test_fallback_channel |> TestChannel.settings, type: "ivr")

      quiz = insert(:questionnaire, steps: @dummy_steps)
      sequence_mode = ["sms", "ivr"]
      survey = insert(:survey, %{schedule: Schedule.always(), state: "running", questionnaires: [quiz], mode: [sequence_mode]})
      group = insert(:respondent_group, survey: survey, respondents_count: 1) |> Repo.preload([:channels])

      RespondentGroupChannel.changeset(%RespondentGroupChannel{}, %{respondent_group_id: group.id, channel_id: channel.id, mode: channel.type}) |> Repo.insert
      RespondentGroupChannel.changeset(%RespondentGroupChannel{}, %{respondent_group_id: group.id, channel_id: fallback_channel.id, mode: fallback_channel.type}) |> Repo.insert

      respondent = insert(:respondent, survey: survey, respondent_group: group)
      phone_number = respondent.sanitized_phone_number

      survey |> Survey.changeset(%{sms_retry_configuration: "1m 50m"}) |> Repo.update!
      survey |> Survey.changeset(%{ivr_retry_configuration: "20m"}) |> Repo.update!

      # First poll, activate the respondent
      Broker.handle_info(:poll, nil)
      assert_received [:setup, ^test_channel, respondent = %Respondent{sanitized_phone_number: ^phone_number}, token]
      assert_received [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

      respondent = Repo.get(Respondent, respondent.id)

      # Set for immediate timeout
      timeout_at = Timex.now |> Timex.shift(hours: -1)
      Respondent.changeset(respondent, %{timeout_at: timeout_at}) |> Repo.update

      # Second poll, retry the question
      Broker.handle_info(:poll, nil)

      refute_received [:setup, _, _, _, _]
      assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

      respondent = Repo.get(Respondent, respondent.id)

      # Set for immediate timeout
      timeout_at = Timex.now |> Timex.shift(hours: -1)
      Respondent.changeset(respondent, %{timeout_at: timeout_at}) |> Repo.update

      # Third poll, retry the question
      Broker.handle_info(:poll, nil)
      refute_received [:setup, _, _, _, _]
      assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

      respondent = Repo.get(Respondent, respondent.id)

      # Set for immediate timeout
      timeout_at = Timex.now |> Timex.shift(hours: -1)
      Respondent.changeset(respondent, %{timeout_at: timeout_at}) |> Repo.update

      # Fourth poll, this time fallback to IVR channel
      Broker.handle_info(:poll, nil)
      assert_received [:setup, ^test_fallback_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token]
    end

    test "fallback respondent (IVR => SMS)" do
      test_channel = TestChannel.new
      channel = insert(:channel, settings: test_channel |> TestChannel.settings, type: "ivr")

      test_fallback_channel = TestChannel.new
      fallback_channel = insert(:channel, settings: test_fallback_channel |> TestChannel.settings, type: "sms")

      quiz = insert(:questionnaire, steps: @dummy_steps)
      survey = insert(:survey, %{schedule: Schedule.always(), state: "running", questionnaires: [quiz], mode: [["ivr", "sms"]]})
      group = insert(:respondent_group, survey: survey, respondents_count: 1) |> Repo.preload([:channels])

      RespondentGroupChannel.changeset(%RespondentGroupChannel{}, %{respondent_group_id: group.id, channel_id: channel.id, mode: channel.type}) |> Repo.insert
      RespondentGroupChannel.changeset(%RespondentGroupChannel{}, %{respondent_group_id: group.id, channel_id: fallback_channel.id, mode: fallback_channel.type}) |> Repo.insert

      respondent = insert(:respondent, survey: survey, respondent_group: group)
      phone_number = respondent.sanitized_phone_number

      survey |> Survey.changeset(%{sms_retry_configuration: "10m"}) |> Repo.update!
      survey |> Survey.changeset(%{ivr_retry_configuration: "2m 20m"}) |> Repo.update!

      # First poll, activate the respondent
      Broker.handle_info(:poll, nil)
      assert_received [:setup, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token]

      # Set for immediate timeout
      respondent = Repo.get(Respondent, respondent.id)
      Respondent.changeset(respondent, %{timeout_at: Timex.now |> Timex.shift(minutes: -1)}) |> Repo.update

      # Second poll, retry the question
      Broker.handle_info(:poll, nil)
      assert_received [:setup, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token]

      # Set for immediate timeout
      respondent = Repo.get(Respondent, respondent.id)
      Respondent.changeset(respondent, %{timeout_at: Timex.now |> Timex.shift(minutes: -1)}) |> Repo.update

      # Third poll, this time fallback to SMS channel
      Broker.handle_info(:poll, nil)
      assert_received [:setup, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token]

      # Set for immediate timeout
      respondent = Repo.get(Respondent, respondent.id)
      Respondent.changeset(respondent, %{timeout_at: Timex.now |> Timex.shift(minutes: -1)}) |> Repo.update

      # Fourth poll, this time fallback to SMS channel
      Broker.handle_info(:poll, nil)
      assert_received [:setup, ^test_fallback_channel, respondent = %Respondent{sanitized_phone_number: ^phone_number}, token]
      assert_received [:ask, ^test_fallback_channel, ^respondent, ^token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]
    end
  end

  describe "mark survey as complete" do
    test "when the cutoff is reached and actives become stalled" do
      [survey, group, _, _, _] = create_running_survey_with_channel_and_respondent()
      create_several_respondents(survey, group, 20)

      Repo.update(survey |> change |> Ask.Survey.changeset(%{cutoff: 1}))

      Broker.handle_info(:poll, nil)

      survey = Repo.get(Ask.Survey, survey.id)
      assert_respondents_by_state(survey, 1, 20)

      r = Repo.all(from r in Respondent, where: r.state == "active") |> hd
      Repo.update(r |> change |> Respondent.changeset(%{state: "completed"}))

      Repo.all(from r in Respondent, where: r.state == "active")
      |> Enum.map(fn respondent ->
        Repo.update(respondent |> change |> Respondent.changeset(%{state: "stalled"}))
      end)

      Broker.handle_info(:poll, nil)

      survey = Repo.get(Ask.Survey, survey.id)

      assert_respondents_by_state(survey, 0, 20)
      assert Ask.Survey.completed?(survey)
    end

    test "when the cutoff is reached and actives become failed" do
      [survey, group, _, _, _] = create_running_survey_with_channel_and_respondent()
      create_several_respondents(survey, group, 20)

      Repo.update(survey |> change |> Ask.Survey.changeset(%{cutoff: 1}))

      Broker.handle_info(:poll, nil)

      survey = Repo.get(Ask.Survey, survey.id)
      assert_respondents_by_state(survey, 1, 20)

      r = Repo.all(from r in Respondent, where: r.state == "active") |> hd
      Repo.update(r |> change |> Respondent.changeset(%{state: "completed"}))

      Repo.all(from r in Respondent, where: r.state == "active")
      |> Enum.map(fn respondent ->
        Repo.update(respondent |> change |> Respondent.changeset(%{state: "failed"}))
      end)

      Broker.handle_info(:poll, nil)

      survey = Repo.get(Ask.Survey, survey.id)

      assert_respondents_by_state(survey, 0, 20)
      assert Ask.Survey.completed?(survey)
    end

    test "when the cutoff is reached and actives become completed" do
      [survey, group, _, _, _] = create_running_survey_with_channel_and_respondent()
      create_several_respondents(survey, group, 20)

      Repo.update(survey |> change |> Ask.Survey.changeset(%{cutoff: 6}))

      Broker.handle_info(:poll, nil)

      survey = Repo.get(Ask.Survey, survey.id)

      assert survey.state == "running"

      assert_respondents_by_state(survey, 6, 15)

      Repo.all(from r in Respondent, where: r.state == "active", limit: 5)
      |> Enum.map(fn respondent ->
        Repo.update(respondent |> change |> Respondent.changeset(%{state: "completed"}))
      end)

      Broker.handle_info(:poll, nil)

      assert_respondents_by_state(survey, 1, 15)

      Repo.all(from r in Respondent, where: r.state == "active")
      |> Enum.map(fn respondent ->
        Repo.update(respondent |> change |> Respondent.changeset(%{state: "completed"}))
      end)

      Broker.handle_info(:poll, nil)

      assert_respondents_by_state(survey, 0, 15)

      survey = Repo.get(Ask.Survey, survey.id)
      assert Ask.Survey.completed?(survey)
    end

    test "when all the quotas are reached and actives become completed" do
      [survey, group, _, _, _] = create_running_survey_with_channel_and_respondent()
      create_several_respondents(survey, group, 10)

      quotas = %{
        "vars" => ["Smokes", "Exercises"],
        "buckets" => [
          %{
            "condition" => [%{"store" => "Smokes", "value" => "No"}, %{"store" => "Exercises", "value" => "No"}],
            "quota" => 1,
            "count" => 0
          },
          %{
            "condition" => [%{"store" => "Smokes", "value" => "No"}, %{"store" => "Exercises", "value" => "Yes"}],
            "quota" => 2,
            "count" => 0
          },
          %{
            "condition" => [%{"store" => "Smokes", "value" => "Yes"}, %{"store" => "Exercises", "value" => "No"}],
            "quota" => 3,
            "count" => 0
          },
          %{
            "condition" => [%{"store" => "Smokes", "value" => "Yes"}, %{"store" => "Exercises", "value" => "Yes"}],
            "quota" => 4,
            "count" => 0
          },
        ]
      }

      survey = survey
               |> Repo.preload([:quota_buckets])
               |> Ask.Survey.changeset(%{quotas: quotas})
               |> Repo.update!

      qb1 = (from q in QuotaBucket, where: q.quota == 1) |> Repo.one
      qb2 = (from q in QuotaBucket, where: q.quota == 2) |> Repo.one
      qb3 = (from q in QuotaBucket, where: q.quota == 3) |> Repo.one
      qb4 = (from q in QuotaBucket, where: q.quota == 4) |> Repo.one

      Broker.handle_info(:poll, nil)

      # In the beginning it shouldn't be completed
      survey = Ask.Survey |> Repo.get(survey.id)
      assert survey.state == "running"

      # Not yet completed: missing fourth bucket
      qb1 |> QuotaBucket.changeset(%{count: 1}) |> Repo.update!
      qb2 |> QuotaBucket.changeset(%{count: 2}) |> Repo.update!
      qb3 |> QuotaBucket.changeset(%{count: 3}) |> Repo.update!
      qb4 |> QuotaBucket.changeset(%{count: 3}) |> Repo.update!
      Broker.handle_info(:poll, nil)

      survey = Ask.Survey |> Repo.get(survey.id)
      assert survey.state == "running"

      # Now it should be completed
      qb4 |> QuotaBucket.changeset(%{count: 4}) |> Repo.update!

      Repo.all(from r in Respondent, where: r.state == "active")
      |> Enum.map(fn respondent ->
        Repo.update(respondent |> change |> Respondent.changeset(%{state: "completed"}))
      end)

      Broker.handle_info(:poll, nil)

      survey_id = survey.id
      from q in QuotaBucket,
           where: q.survey_id == ^survey_id

      survey = Ask.Survey |> Repo.get(survey.id)
      assert Ask.Survey.completed?(survey)
    end

    test "when all the quotas are reached and actives become stalled" do
      [survey, group, _, _, _] = create_running_survey_with_channel_and_respondent()
      create_several_respondents(survey, group, 20)

      quotas = %{
        "vars" => ["Smokes", "Exercises"],
        "buckets" => [
          %{
            "condition" => [%{"store" => "Smokes", "value" => "No"}, %{"store" => "Exercises", "value" => "No"}],
            "quota" => 1,
            "count" => 0
          },
          %{
            "condition" => [%{"store" => "Smokes", "value" => "No"}, %{"store" => "Exercises", "value" => "Yes"}],
            "quota" => 2,
            "count" => 0
          },
          %{
            "condition" => [%{"store" => "Smokes", "value" => "Yes"}, %{"store" => "Exercises", "value" => "No"}],
            "quota" => 3,
            "count" => 0
          },
          %{
            "condition" => [%{"store" => "Smokes", "value" => "Yes"}, %{"store" => "Exercises", "value" => "Yes"}],
            "quota" => 4,
            "count" => 0
          },
        ]
      }

      survey = survey
               |> Repo.preload([:quota_buckets])
               |> Ask.Survey.changeset(%{quotas: quotas})
               |> Repo.update!

      qb1 = (from q in QuotaBucket, where: q.quota == 1) |> Repo.one
      qb2 = (from q in QuotaBucket, where: q.quota == 2) |> Repo.one
      qb3 = (from q in QuotaBucket, where: q.quota == 3) |> Repo.one
      qb4 = (from q in QuotaBucket, where: q.quota == 4) |> Repo.one

      Broker.handle_info(:poll, nil)

      survey = Ask.Survey |> Repo.get(survey.id)
      assert survey.state == "running"

      qb1 |> QuotaBucket.changeset(%{count: 1}) |> Repo.update!
      qb2 |> QuotaBucket.changeset(%{count: 2}) |> Repo.update!
      qb3 |> QuotaBucket.changeset(%{count: 3}) |> Repo.update!
      qb4 |> QuotaBucket.changeset(%{count: 4}) |> Repo.update!

      Repo.all(from r in Respondent, where: r.state == "active")
      |> Enum.map(fn respondent ->
        Repo.update(respondent |> change |> Respondent.changeset(%{state: "stalled"}))
      end)

      Broker.handle_info(:poll, nil)

      survey = Ask.Survey |> Repo.get(survey.id)
      assert_respondents_by_state(survey, 0, 11)
      assert Ask.Survey.completed?(survey)
    end

    test "when all the quotas are reached and actives become failed" do
      [survey, group, _, _, _] = create_running_survey_with_channel_and_respondent()
      create_several_respondents(survey, group, 20)

      quotas = %{
        "vars" => ["Smokes", "Exercises"],
        "buckets" => [
          %{
            "condition" => [%{"store" => "Smokes", "value" => "No"}, %{"store" => "Exercises", "value" => "No"}],
            "quota" => 1,
            "count" => 0
          },
          %{
            "condition" => [%{"store" => "Smokes", "value" => "No"}, %{"store" => "Exercises", "value" => "Yes"}],
            "quota" => 2,
            "count" => 0
          },
          %{
            "condition" => [%{"store" => "Smokes", "value" => "Yes"}, %{"store" => "Exercises", "value" => "No"}],
            "quota" => 3,
            "count" => 0
          },
          %{
            "condition" => [%{"store" => "Smokes", "value" => "Yes"}, %{"store" => "Exercises", "value" => "Yes"}],
            "quota" => 4,
            "count" => 0
          },
        ]
      }

      survey = survey
               |> Repo.preload([:quota_buckets])
               |> Ask.Survey.changeset(%{quotas: quotas})
               |> Repo.update!

      qb1 = (from q in QuotaBucket, where: q.quota == 1) |> Repo.one
      qb2 = (from q in QuotaBucket, where: q.quota == 2) |> Repo.one
      qb3 = (from q in QuotaBucket, where: q.quota == 3) |> Repo.one
      qb4 = (from q in QuotaBucket, where: q.quota == 4) |> Repo.one

      Broker.handle_info(:poll, nil)

      survey = Ask.Survey |> Repo.get(survey.id)
      assert survey.state == "running"

      qb1 |> QuotaBucket.changeset(%{count: 1}) |> Repo.update!
      qb2 |> QuotaBucket.changeset(%{count: 2}) |> Repo.update!
      qb3 |> QuotaBucket.changeset(%{count: 3}) |> Repo.update!
      qb4 |> QuotaBucket.changeset(%{count: 4}) |> Repo.update!

      Repo.all(from r in Respondent, where: r.state == "active")
      |> Enum.map(fn respondent ->
        Repo.update(respondent |> change |> Respondent.changeset(%{state: "failed"}))
      end)

      Broker.handle_info(:poll, nil)

      survey = Ask.Survey |> Repo.get(survey.id)
      assert_respondents_by_state(survey, 0, 11)
      assert Ask.Survey.completed?(survey)
    end

    test "when there are no more running respondents" do
      [survey, _, _, respondent, _] = create_running_survey_with_channel_and_respondent()

      Broker.handle_info(:poll, nil)

      assert_respondents_by_state(survey, 1, 0)

      respondent = Repo.get(Respondent, respondent.id)
      Repo.update(respondent |> change |> Respondent.changeset(%{state: "failed"}))

      Broker.handle_info(:poll, nil)

      survey = Repo.get(Ask.Survey, survey.id)
      assert Ask.Survey.completed?(survey)
    end

    test "when there are no respondents" do
      survey = insert(:survey, %{schedule: Schedule.always(), state: "running"})
      Broker.handle_info(:poll, nil)

      survey = Repo.get(Ask.Survey, survey.id)
      assert Ask.Survey.completed?(survey)
    end
  end

  describe "polling surveys" do
    test "only polls surveys schedule for todays weekday" do
      week_day = Timex.weekday(Timex.today)
      schedule1 = %Ask.DayOfWeek{
        mon: week_day == 1,
        tue: week_day == 2,
        wed: week_day == 3,
        thu: week_day == 4,
        fri: week_day == 5,
        sat: week_day == 6,
        sun: week_day == 7}
      schedule2 = %Ask.DayOfWeek{
        mon: week_day != 1,
        tue: week_day != 2,
        wed: week_day != 3,
        thu: week_day != 4,
        fri: week_day != 5,
        sat: week_day != 6,
        sun: week_day != 7}
      survey1 = insert(:survey, %{schedule: Map.merge(Schedule.always(), %{day_of_week: schedule1}), state: "running"})
      survey2 = insert(:survey, %{schedule: Map.merge(Schedule.always(), %{day_of_week: schedule2}), state: "running"})

      Broker.handle_info(:poll, nil)

      survey1 = Repo.get(Ask.Survey, survey1.id)
      survey2 = Repo.get(Ask.Survey, survey2.id)
      assert Ask.Survey.completed?(survey1)
      assert survey2.state == "running"
    end

    test "only polls surveys if today is not blocked" do
      survey1 = insert(:survey, %{schedule: Schedule.always(), state: "running"})
      survey2 = insert(:survey, %{schedule: Map.merge(Schedule.always(), %{blocked_days: [Date.utc_today()]}), state: "running"})

      Broker.handle_info(:poll, nil)

      survey1 = Repo.get(Ask.Survey, survey1.id)
      survey2 = Repo.get(Ask.Survey, survey2.id)
      assert Ask.Survey.completed?(survey1)
      assert survey2.state == "running"
    end

    test "doesn't poll surveys with a start time schedule greater than the current hour" do
      now = Timex.now
      ten_oclock = Timex.shift(now |> Timex.beginning_of_day, hours: 10)
      eleven_oclock = Timex.shift(ten_oclock, hours: 1)
      twelve_oclock = Timex.shift(eleven_oclock, hours: 2)
      {:ok, start_time} = Ecto.Time.cast(eleven_oclock)
      {:ok, end_time} = Ecto.Time.cast(twelve_oclock)
      survey = insert(:survey, %{schedule: Map.merge(Schedule.always(), %{start_time: start_time, end_time: end_time}), state: "running"})

      Broker.handle_info(:poll, nil, ten_oclock)

      survey = Repo.get(Ask.Survey, survey.id)
      assert survey.state == "running"
    end

    test "doesn't poll surveys with an end time schedule smaller than the current hour" do
      now = Timex.now
      ten_oclock = Timex.shift(now |> Timex.beginning_of_day, hours: 10)
      eleven_oclock = Timex.shift(ten_oclock, hours: 1)
      twelve_oclock = Timex.shift(eleven_oclock, hours: 2)
      {:ok, start_time} = Ecto.Time.cast(ten_oclock)
      {:ok, end_time} = Ecto.Time.cast(eleven_oclock)
      survey = insert(:survey, %{schedule: Map.merge(Schedule.always(), %{start_time: start_time, end_time: end_time}), state: "running"})

      Broker.handle_info(:poll, nil, twelve_oclock)

      survey = Repo.get(Ask.Survey, survey.id)
      assert survey.state == "running"
    end

    test "doesn't poll surveys with an end time schedule smaller than the current hour considering timezone" do
      survey = insert(:survey, %{schedule: Map.merge(Schedule.always(), %{start_time: ~T[10:00:00], end_time: ~T[12:00:00], timezone: "Asia/Shanghai"}), state: "running"})

      Broker.handle_info(:poll, nil, Timex.parse!("2016-01-01T11:00:00Z", "{ISO:Extended}"))

      survey = Repo.get(Ask.Survey, survey.id)
      assert survey.state == "running"
    end

    test "does poll surveys with an end time schedule higher than the current hour considering timezone" do
      survey = insert(:survey, %{schedule: Map.merge(Schedule.always(), %{start_time: ~T[10:00:00], end_time: ~T[12:00:00], timezone: "America/Buenos_Aires"}), state: "running"})

      Broker.handle_info(:poll, nil, Timex.parse!("2016-01-01T14:00:00Z", "{ISO:Extended}"))

      survey = Repo.get(Ask.Survey, survey.id)
      assert Ask.Survey.completed?(survey)
    end

    test "does poll surveys considering day of week according to timezone" do
      # Survey runs on Wednesday on every hour, Mexico time (GMT-5)
      attrs = %{
        schedule: %Schedule{
          day_of_week: %Ask.DayOfWeek{wed: true},
          start_time: ~T[00:00:00],
          end_time: ~T[23:59:00],
          timezone: "America/Mexico_City"
        },
        state: "running",
      }
      survey = insert(:survey, attrs)

      # Now is Thursday 1AM UTC, so in Mexico it's still Wednesday
      mock_now = Timex.parse!("2017-04-27T01:00:00Z", "{ISO:Extended}")

      Broker.handle_info(:poll, nil, mock_now)

      # The survey should have run and be completed (questionnaire is empty)
      survey = Repo.get(Ask.Survey, survey.id)
      assert Ask.Survey.completed?(survey)
    end

    test "doesn't poll surveys considering day of week according to timezone" do
      # Survey runs on Wednesday on every hour, Mexico time (GMT-5)
      attrs = %{
        schedule: %Schedule{
          day_of_week: %Ask.DayOfWeek{wed: true},
          start_time: ~T[00:00:00],
          end_time: ~T[23:59:00],
          timezone: "America/Mexico_City"
        },
        state: "running",
      }
      survey = insert(:survey, attrs)

      # Now is Thursday 6AM UTC, so in Mexico it's now Thursday
      mock_now = Timex.parse!("2017-04-27T06:00:00Z", "{ISO:Extended}")

      Broker.handle_info(:poll, nil, mock_now)

      # Survey shouldn't have started yet
      survey = Repo.get(Ask.Survey, survey.id)
      assert survey.state == "running"
    end

    test "continue polling respondents when one of the quotas was exceeded " do
      [survey, group, _, _, _] = create_running_survey_with_channel_and_respondent()
      create_several_respondents(survey, group, 10)
      survey |> Ask.Survey.changeset(%{quota_vars: ["gender"]}) |> Repo.update
      insert(:quota_bucket, survey: survey, condition: %{gender: "male"}, quota: 1, count: 2)
      insert(:quota_bucket, survey: survey, condition: %{gender: "female"}, quota: 1, count: 0)

      Broker.handle_info(:poll, nil)
      assert_respondents_by_state(survey, 1, 10)
    end

    test "doesn't poll if at least a channel is down", %{channel_status_server: channel_status_server} do
      Process.register self(), :mail_target
      quiz = insert(:questionnaire, steps: @dummy_steps, quota_completed_steps: nil)
      survey = insert(:survey, %{schedule: Schedule.always(), state: "running", questionnaires: [quiz], mode: [["sms"]]})
      channel_1 = insert(:channel, settings: TestChannel.new |> TestChannel.settings(1, :up), type: "sms")
      channel_2 = insert(:channel, settings: TestChannel.new |> TestChannel.settings(2, :down), type: "sms")
      test_channel_1 = channel_1 |> TestChannel.new
      test_channel_2 = channel_2 |> TestChannel.new
      group_1 = insert(:respondent_group, survey: survey, respondents_count: 1) |> Repo.preload(:channels)
      group_2 = insert(:respondent_group, survey: survey, respondents_count: 1) |> Repo.preload(:channels)
      insert(:respondent, survey: survey, respondent_group: group_1)
      insert(:respondent, survey: survey, respondent_group: group_2)
      insert(:respondent_group_channel, channel: channel_1, respondent_group: group_1, mode: "sms")
      insert(:respondent_group_channel, channel: channel_2, respondent_group: group_2, mode: "sms")

      {:ok, broker} = Broker.start_link
      ChannelStatusServer.poll(channel_status_server)
      Broker.poll

      refute_received [:ask, ^test_channel_1, _, _, _]
      refute_received [:ask, ^test_channel_2, _, _, _]

      :ok = broker |> GenServer.stop
      :ok = channel_status_server |> GenServer.stop
    end
  end

  describe "after 8 hours" do
    test "mark stalled respondent as failed" do
      [_survey, _group, test_channel, _respondent, phone_number] = create_running_survey_with_channel_and_respondent()

      {:ok, _} = Broker.start_link

      # First poll, activate the respondent
      Broker.handle_info(:poll, nil)
      assert_received [:setup, ^test_channel, respondent = %Respondent{sanitized_phone_number: ^phone_number}, token]
      assert_received [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

      # Set for immediate timeout
      respondent = Repo.get!(Respondent, respondent.id)
      Respondent.changeset(respondent, %{timeout_at: Timex.now |> Timex.shift(minutes: -1)}) |> Repo.update

      # This time it should stall
      Broker.handle_info(:poll, nil)

      respondent = Repo.get(Respondent, respondent.id)

      now = Timex.now

      # After seven hours it's still stalled
      seven_hours_ago = now |> Timex.shift(hours: -7) |> Timex.to_erl |> NaiveDateTime.from_erl!
      (from r in Respondent, where: r.id == ^respondent.id) |> Repo.update_all(set: [updated_at: seven_hours_ago])

      Broker.handle_info(:poll, nil)

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.state == "stalled"
      assert respondent.disposition == "queued"

      # After eight hours it should be marked as failed
      eight_hours_ago = now |> Timex.shift(hours: -8) |> Timex.to_erl |> NaiveDateTime.from_erl!
      (from r in Respondent, where: r.id == ^respondent.id) |> Repo.update_all(set: [updated_at: eight_hours_ago])

      Broker.handle_info(:poll, nil)

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.state == "failed"
      assert respondent.disposition == "failed"
    end

    test "queued respondents are marked failed" do
      [survey, _, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent()
      Repo.update(survey |> change |> Survey.changeset(%{cutoff: 1}))

      {:ok, broker} = Broker.start_link
      {:ok, logger} = SurveyLogger.start_link
      Broker.poll

      assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

      survey = Repo.get(Survey, survey.id)
      assert survey.state == "running"
      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.state == "active"
      assert respondent.disposition == "queued"

      now = Timex.now

      # Set for immediate timeout
      Respondent.changeset(respondent, %{timeout_at: now |> Timex.shift(minutes: -1)}) |> Repo.update
      Broker.handle_info(:poll, nil)

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.state == "stalled"
      assert respondent.disposition == "queued"

      # After eight hours it should be marked as failed
      eight_hours_ago = now |> Timex.shift(hours: -8) |> Timex.to_erl |> NaiveDateTime.from_erl!
      (from r in Respondent, where: r.id == ^respondent.id) |> Repo.update_all(set: [updated_at: eight_hours_ago])

      Broker.handle_info(:poll, nil)

      :ok = logger |> GenServer.stop
      [disposition_changed_to_failed] = (respondent |> Repo.preload(:survey_log_entries)).survey_log_entries

      assert disposition_changed_to_failed.survey_id == survey.id
      assert disposition_changed_to_failed.action_data == "Failed"
      assert disposition_changed_to_failed.action_type == "disposition changed"
      assert disposition_changed_to_failed.disposition == "queued"

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.state == "failed"
      assert respondent.disposition == "failed"

      :ok = broker |> GenServer.stop
    end

    test "contacted respondents are marked as unresponsive" do
      [survey, _, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent()
      Repo.update(survey |> change |> Ask.Survey.changeset(%{cutoff: 1}))

      {:ok, broker} = Broker.start_link
      {:ok, logger} = SurveyLogger.start_link
      Broker.poll

      assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

      survey = Repo.get(Ask.Survey, survey.id)
      assert survey.state == "running"
      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.state == "active"
      assert respondent.disposition == "queued"

      Ask.Runtime.Respondent.delivery_confirm(respondent, "Do you smoke?")

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.disposition == "contacted"

      now = Timex.now

      # Set for immediate timeout
      Respondent.changeset(respondent, %{timeout_at: now |> Timex.shift(minutes: -1)}) |> Repo.update
      Broker.handle_info(:poll, nil)

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.state == "stalled"
      assert respondent.disposition == "contacted"

      # After eight hours it should be marked as failed
      eight_hours_ago = now |> Timex.shift(hours: -8) |> Timex.to_erl |> NaiveDateTime.from_erl!
      (from r in Respondent, where: r.id == ^respondent.id) |> Repo.update_all(set: [updated_at: eight_hours_ago])

      Broker.handle_info(:poll, nil)

      :ok = logger |> GenServer.stop
      [_, _, disposition_changed_to_unresponsive] = (respondent |> Repo.preload(:survey_log_entries)).survey_log_entries

      assert disposition_changed_to_unresponsive.survey_id == survey.id
      assert disposition_changed_to_unresponsive.action_data == "Unresponsive"
      assert disposition_changed_to_unresponsive.action_type == "disposition changed"
      assert disposition_changed_to_unresponsive.disposition == "contacted"

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.state == "failed"
      assert respondent.disposition == "unresponsive"

      :ok = broker |> GenServer.stop
    end

    test "started respondents are marked as breakoff" do
      [survey, _, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent()
      Repo.update(survey |> change |> Ask.Survey.changeset(%{cutoff: 1}))

      {:ok, broker} = Broker.start_link
      {:ok, logger} = SurveyLogger.start_link
      Broker.poll

      assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

      survey = Repo.get(Ask.Survey, survey.id)
      assert survey.state == "running"
      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.state == "active"
      assert respondent.disposition == "queued"

      Ask.Runtime.Respondent.delivery_confirm(respondent, "Do you smoke?")

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.state == "active"
      assert respondent.disposition == "contacted"

      respondent = Repo.get(Respondent, respondent.id)
      Ask.Runtime.Survey.sync_step(respondent, Flow.Message.reply("yes"))

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.state == "active"
      assert respondent.disposition == "started"

      Ask.Runtime.Respondent.delivery_confirm(respondent, "Do you exercise?")

      now = Timex.now

      Respondent.changeset(respondent, %{timeout_at: now |> Timex.shift(minutes: -1)}) |> Repo.update
      Broker.handle_info(:poll, nil)

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.state == "stalled"
      assert respondent.disposition == "started"

      # After eight hours it should be marked as failed
      eight_hours_ago = now |> Timex.shift(hours: -8) |> Timex.to_erl |> NaiveDateTime.from_erl!
      (from r in Respondent, where: r.id == ^respondent.id) |> Repo.update_all(set: [updated_at: eight_hours_ago])

      Broker.handle_info(:poll, nil)

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.state == "failed"
      assert respondent.disposition == "breakoff"

      :ok = logger |> GenServer.stop

      last_entry = ((respondent |> Repo.preload(:survey_log_entries)).survey_log_entries) |> Enum.at(-1)

      assert last_entry.survey_id == survey.id
      assert last_entry.action_data == "Breakoff"
      assert last_entry.action_type == "disposition changed"
      assert last_entry.disposition == "started"

      :ok = broker |> GenServer.stop
    end

    test "interim partial respondents are kept as partial (SMS)" do
      [survey, _, _, respondent, _] = create_running_survey_with_channel_and_respondent(@flag_step_after_multiple_choice)

      {:ok, broker} = Broker.start_link
      {:ok, logger} = SurveyLogger.start_link
      Broker.poll

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.state == "active"
      assert respondent.disposition == "queued"

      Ask.Runtime.Respondent.delivery_confirm(respondent, "Do you smoke?")

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.state == "active"
      assert respondent.disposition == "contacted"

      respondent = Repo.get(Respondent, respondent.id)
      Ask.Runtime.Survey.sync_step(respondent, Flow.Message.reply("Yes"))

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.state == "active"
      assert respondent.disposition == "interim partial"

      Ask.Runtime.Respondent.delivery_confirm(respondent, "Do you exercise?")

      now = Timex.now

      Respondent.changeset(respondent, %{timeout_at: now |> Timex.shift(minutes: -1)}) |> Repo.update
      Broker.handle_info(:poll, nil)

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.state == "stalled"
      assert respondent.disposition == "interim partial"

      # After eight hours it should be marked as failed
      eight_hours_ago = now |> Timex.shift(hours: -8) |> Timex.to_erl |> NaiveDateTime.from_erl!
      (from r in Respondent, where: r.id == ^respondent.id) |> Repo.update_all(set: [updated_at: eight_hours_ago])

      Broker.handle_info(:poll, nil)

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.state == "failed"
      assert respondent.disposition == "partial"

      :ok = logger |> GenServer.stop
      last_entry = ((respondent |> Repo.preload(:survey_log_entries)).survey_log_entries |> Enum.at(-1))

      assert last_entry.survey_id == survey.id
      assert last_entry.action_data == "Partial"
      assert last_entry.action_type == "disposition changed"
      assert last_entry.disposition == "interim partial"

      :ok = broker |> GenServer.stop
    end

  end

  describe "change respondent disposition" do
    test "set the respondent as completed (disposition) when the questionnaire is empty" do
      [_, _, _, respondent, _] = create_running_survey_with_channel_and_respondent([])

      Broker.handle_info(:poll, nil)

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.disposition == "completed"
    end

    test "set the respondent as complete (disposition) if disposition is interim partial" do
      [_, _, _, respondent, _] = create_running_survey_with_channel_and_respondent(@partial_step)

      Broker.handle_info(:poll, nil)

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.disposition == "completed"
    end

    test "set the respondent from registered to queued" do
      [survey, _, _, respondent, _] = create_running_survey_with_channel_and_respondent()

      Broker.handle_info(:poll, nil)

      survey = Repo.get(Ask.Survey, survey.id)
      assert survey.state == "running"
      updated_respondent = Repo.get(Respondent, respondent.id)
      assert updated_respondent.disposition == "queued"
    end

    test "don't set the respondent as completed (disposition) if disposition is ineligible" do
      [_, _, _, respondent, _] = create_running_survey_with_channel_and_respondent(@ineligible_step)

      Broker.handle_info(:poll, nil)

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.disposition == "ineligible"
    end

    test "don't set the respondent as completed (disposition) if disposition is refused" do
      [_, _, _, respondent, _] = create_running_survey_with_channel_and_respondent(@refused_step)

      Broker.handle_info(:poll, nil)

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.disposition == "refused"
    end

    test "don't set the respondent as partial (disposition) if disposition is ineligible" do
      [_, _, _, respondent, _] = create_running_survey_with_channel_and_respondent(@ineligible_step ++ @partial_step)

      Broker.handle_info(:poll, nil)

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.disposition == "ineligible"
    end

    test "don't set the respondent as partial (disposition) if disposition is refused" do
      [_, _, _, respondent, _] = create_running_survey_with_channel_and_respondent(@refused_step ++ @partial_step)

      Broker.handle_info(:poll, nil)

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.disposition == "refused"
    end

    test "don't set the respondent as ineligible (disposition) if disposition is completed" do
      [_, _, _, respondent, _] = create_running_survey_with_channel_and_respondent(@completed_step ++ @ineligible_step)

      Broker.handle_info(:poll, nil)

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.disposition == "completed"
    end
  end

  describe "change the respondent state" do
    test "changes the respondent state from pending to running if neccessary" do
      [survey, _, _, respondent, _] = create_running_survey_with_channel_and_respondent()

      Broker.handle_info(:poll, nil)

      survey = Repo.get(Ask.Survey, survey.id)
      assert survey.state == "running"
      updated_respondent = Repo.get(Respondent, respondent.id)
      assert updated_respondent.state == "active"

      now = Timex.now
      interval = Interval.new(from: Timex.shift(now, minutes: 9), until: Timex.shift(now, minutes: 11), step: [seconds: 1])
      assert updated_respondent.timeout_at in interval
    end

    test "set the respondent as completed when the questionnaire is empty" do
      [_, _, _, respondent, _] = create_running_survey_with_channel_and_respondent([])

      Broker.handle_info(:poll, nil)

      respondent = Repo.get(Respondent, respondent.id)
      assert respondent.state == "completed"
    end
  end

  test "does nothing with 'not_ready' survey" do
    survey = insert(:survey, %{schedule: Schedule.always()})
    Broker.handle_info(:poll, nil)

    survey = Repo.get(Ask.Survey, survey.id)
    assert survey.state == "not_ready"
  end

  test "does nothing when there are no pending respondents" do
    survey = insert(:survey, %{schedule: Schedule.always(), state: "running"})
    insert(:respondent, survey: survey, state: "active")

    Broker.handle_info(:poll, nil)

    survey = Repo.get(Ask.Survey, survey.id)
    assert survey.state == "running"
  end

  test "should not keep setting pending to actives when all the quotas are completed" do
    [survey, group, _, _, _] = create_running_survey_with_channel_and_respondent()
    create_several_respondents(survey, group, 20)

    quotas = %{
      "vars" => ["Smokes", "Exercises"],
      "buckets" => [
        %{
          "condition" => [%{"store" => "Smokes", "value" => "No"}, %{"store" => "Exercises", "value" => "No"}],
          "quota" => 1,
          "count" => 0
        },
        %{
          "condition" => [%{"store" => "Smokes", "value" => "No"}, %{"store" => "Exercises", "value" => "Yes"}],
          "quota" => 2,
          "count" => 0
        },
        %{
          "condition" => [%{"store" => "Smokes", "value" => "Yes"}, %{"store" => "Exercises", "value" => "No"}],
          "quota" => 3,
          "count" => 0
        },
        %{
          "condition" => [%{"store" => "Smokes", "value" => "Yes"}, %{"store" => "Exercises", "value" => "Yes"}],
          "quota" => 4,
          "count" => 0
        },
      ]
    }

    survey = survey
             |> Repo.preload([:quota_buckets])
             |> Ask.Survey.changeset(%{quotas: quotas})
             |> Repo.update!

    qb1 = (from q in QuotaBucket, where: q.quota == 1) |> Repo.one
    qb2 = (from q in QuotaBucket, where: q.quota == 2) |> Repo.one
    qb3 = (from q in QuotaBucket, where: q.quota == 3) |> Repo.one
    qb4 = (from q in QuotaBucket, where: q.quota == 4) |> Repo.one

    Broker.handle_info(:poll, nil)

    survey = Ask.Survey |> Repo.get(survey.id)
    assert survey.state == "running"

    qb1 |> QuotaBucket.changeset(%{count: 1}) |> Repo.update!
    qb2 |> QuotaBucket.changeset(%{count: 2}) |> Repo.update!
    qb3 |> QuotaBucket.changeset(%{count: 3}) |> Repo.update!
    qb4 |> QuotaBucket.changeset(%{count: 4}) |> Repo.update!

    Repo.all(from r in Respondent, where: r.state == "active", limit: 5)
    |> Enum.map(fn respondent ->
      Repo.update(respondent |> change |> Respondent.changeset(%{state: "completed"}))
    end)

    Broker.handle_info(:poll, nil)

    survey = Ask.Survey |> Repo.get(survey.id)
    assert_respondents_by_state(survey, 5, 11)
  end

  test "should not keep setting pending to actives when cutoff is reached" do
    [survey, group, _, _, _] = create_running_survey_with_channel_and_respondent()
    create_several_respondents(survey, group, 20)

    Repo.update(survey |> change |> Ask.Survey.changeset(%{cutoff: 1}))

    Broker.handle_info(:poll, nil)

    survey = Repo.get(Ask.Survey, survey.id)
    assert_respondents_by_state(survey, 1, 20)

    r = Repo.all(from r in Respondent, where: r.state == "active") |> hd
    Repo.update(r |> change |> Respondent.changeset(%{state: "completed"}))

    Broker.handle_info(:poll, nil)

    assert_respondents_by_state(survey, 0, 20)
    assert survey.state == "running"
  end

  test "always keeps batch_size number of respondents running" do
    [survey, group, _, _, _] = create_running_survey_with_channel_and_respondent()
    create_several_respondents(survey, group, 20)

    Broker.handle_info(:poll, nil)

    survey = Repo.get(Ask.Survey, survey.id)

    assert survey.state == "running"

    assert_respondents_by_state(survey, 10, 11)

    active_respondent = Repo.all(from r in Respondent, where: r.state == "active")
                        |> Enum.at(0)

    Repo.update(active_respondent |> change |> Respondent.changeset(%{state: "failed"}))

    assert_respondents_by_state(survey, 9, 11)

    Broker.handle_info(:poll, nil)

    assert_respondents_by_state(survey, 10, 10)
  end

  test "" do
    [survey, group, _, _, _] = create_running_survey_with_channel_and_respondent()
    create_several_respondents(survey, group, 10)
    survey |> Ask.Survey.changeset(%{quota_vars: ["gender"]}) |> Repo.update
    insert(:quota_bucket, survey: survey, condition: %{gender: "male"}, quota: 1, count: 0)

    Broker.handle_info(:poll, nil)
    assert_respondents_by_state(survey, 1, 10)

    mark_n_active_respondents_as("completed", 1)

    Broker.handle_info(:poll, nil)
    assert_respondents_by_state(survey, 1, 9)
  end

  test "when a survey has any target of completed respondents the batch size depends on the success rate" do
    [survey, group, _, _, _] = create_running_survey_with_channel_and_respondent()
    create_several_respondents(survey, group, 200)

    Repo.update(survey |> change |> Ask.Survey.changeset(%{cutoff: 50}))

    Broker.handle_info(:poll, nil)
    assert_respondents_by_state(survey, 50, 151)

    mark_n_active_respondents_as("failed", 20)
    mark_n_active_respondents_as("completed", 30)
    Broker.handle_info(:poll, nil)
    assert_respondents_by_state(survey, 20, 131)

    # since all the previous ones failed the success rate decreases
    # and the batch size increases
    mark_n_active_respondents_as("failed", 26)
    Broker.handle_info(:poll, nil)
    assert_respondents_by_state(survey, 20, 111)
  end

  test "uncontacted respondents are marked as failed after all retries are met (IVR)" do
    [_, _, _, respondent, _] = create_running_survey_with_channel_and_respondent(@dummy_steps, "ivr")
    {:ok, broker} = Broker.start_link
    Broker.poll

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.disposition == "queued"

    # Set for immediate timeout
    Respondent.changeset(respondent, %{timeout_at: Timex.now |> Timex.shift(minutes: -1)}) |> Repo.update
    Broker.handle_info(:poll, nil)

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "failed"
    assert respondent.disposition == "failed"

    :ok = broker |> GenServer.stop
  end

  test "creates respondent history when the questionnaire is empty" do
    [_, _, _, respondent, _] = create_running_survey_with_channel_and_respondent([])

    Broker.handle_info(:poll, nil)

    histories = RespondentDispositionHistory |> Repo.all
    assert length(histories) == 2

    history = histories |> Enum.take(-1) |> hd
    assert history.respondent_id == respondent.id
    assert history.survey_id == respondent.survey_id
    assert history.respondent_hashed_number == respondent.hashed_number
    assert history.disposition == "completed"
    assert history.mode == nil
  end

  test "set the respondent questionnaire and mode" do
    [survey, _, _, respondent, _] = create_running_survey_with_channel_and_respondent([])
    mode = hd(survey.mode)
    questionnaire = hd(survey.questionnaires)

    Broker.handle_info(:poll, nil)

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.mode == mode
    assert respondent.questionnaire_id == questionnaire.id
  end

  test "set the respondent questionnaire and mode with comparisons" do
    test_channel = TestChannel.new
    sms_channel = insert(:channel, settings: test_channel |> TestChannel.settings, type: "sms")
    ivr_channel = insert(:channel, settings: test_channel |> TestChannel.settings, type: "ivr")

    quiz1 = insert(:questionnaire, steps: @dummy_steps)
    quiz2 = insert(:questionnaire, steps: @dummy_steps)
    survey = insert(:survey, %{schedule: Schedule.always(),
      state: "running",
      questionnaires: [quiz1, quiz2],
      mode: [["sms"], ["ivr"]],
      comparisons: [
        %{"mode" => ["sms"], "questionnaire_id" => quiz1.id, "ratio" => 0},
        %{"mode" => ["sms"], "questionnaire_id" => quiz2.id, "ratio" => 0},
        %{"mode" => ["ivr"], "questionnaire_id" => quiz1.id, "ratio" => 100},
        %{"mode" => ["ivr"], "questionnaire_id" => quiz2.id, "ratio" => 0},
      ]
    })
    group = insert(:respondent_group, survey: survey, respondents_count: 1) |> Repo.preload(:channels)

    RespondentGroupChannel.changeset(%RespondentGroupChannel{}, %{respondent_group_id: group.id, channel_id: sms_channel.id, mode: sms_channel.type}) |> Repo.insert
    RespondentGroupChannel.changeset(%RespondentGroupChannel{}, %{respondent_group_id: group.id, channel_id: ivr_channel.id, mode: ivr_channel.type}) |> Repo.insert

    respondent = insert(:respondent, survey: survey, respondent_group: group)

    Broker.handle_info(:poll, nil)

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.mode == ["ivr"]
    assert respondent.questionnaire_id == quiz1.id
    assert respondent.stats.attempts["ivr"] == 1
  end

  test "doesn't break with nil as comparison ratio" do
    test_channel = TestChannel.new
    sms_channel = insert(:channel, settings: test_channel |> TestChannel.settings, type: "sms")
    ivr_channel = insert(:channel, settings: test_channel |> TestChannel.settings, type: "ivr")

    quiz1 = insert(:questionnaire, steps: @dummy_steps)
    quiz2 = insert(:questionnaire, steps: @dummy_steps)
    survey = insert(:survey, %{schedule: Schedule.always(),
      state: "running",
      questionnaires: [quiz1, quiz2],
      mode: [["sms"], ["ivr"]],
      comparisons: [
        %{"mode" => ["sms"], "questionnaire_id" => quiz1.id, "ratio" => nil},
        %{"mode" => ["sms"], "questionnaire_id" => quiz2.id, "ratio" => nil},
        %{"mode" => ["ivr"], "questionnaire_id" => quiz1.id, "ratio" => 100},
        %{"mode" => ["ivr"], "questionnaire_id" => quiz2.id, "ratio" => nil},
      ]
    })
    group = insert(:respondent_group, survey: survey, respondents_count: 1) |> Repo.preload(:channels)

    RespondentGroupChannel.changeset(%RespondentGroupChannel{}, %{respondent_group_id: group.id, channel_id: sms_channel.id, mode: sms_channel.type}) |> Repo.insert
    RespondentGroupChannel.changeset(%RespondentGroupChannel{}, %{respondent_group_id: group.id, channel_id: ivr_channel.id, mode: ivr_channel.type}) |> Repo.insert

    respondent = insert(:respondent, survey: survey, respondent_group: group)

    Broker.handle_info(:poll, nil)

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.mode == ["ivr"]
    assert respondent.questionnaire_id == quiz1.id
  end

  defp mark_n_active_respondents_as(new_state, n) do
    Repo.all(from r in Respondent, where: r.state == "active", limit: ^n)
    |> Enum.map(fn respondent ->
      Repo.update(respondent |> change |> Respondent.changeset(%{state: new_state}))
    end)
  end

end
