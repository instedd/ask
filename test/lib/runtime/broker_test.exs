defmodule Ask.BrokerTest do
  use Ask.ModelCase
  use Ask.DummySteps
  use Timex
  alias Ask.Runtime.{Broker, Flow, SurveyLogger, ReplyHelper, ChannelStatusServer}
  alias Ask.{Repo, Survey, Respondent, RespondentDispositionHistory, TestChannel, QuotaBucket, Questionnaire, RespondentGroupChannel, SurveyLogEntry, Schedule, StepBuilder, RetryStat}
  alias Ask.Router.Helpers, as: Routes
  require Ask.Runtime.ReplyHelper

  setup do
    {:ok, channel_status_server} = ChannelStatusServer.start_link
    {:ok, channel_status_server: channel_status_server}
  end

  test "does nothing with 'not_ready' survey" do
    survey = insert(:survey, %{schedule: Schedule.always()})
    Broker.handle_info(:poll, nil)

    survey = Repo.get(Survey, survey.id)
    assert survey.state == "not_ready"
  end

  test "set as 'completed' when there are no respondents" do
    survey = insert(:survey, %{schedule: Schedule.always(), state: "running"})
    Broker.handle_info(:poll, nil)

    survey = Repo.get(Survey, survey.id)
    assert Survey.completed?(survey)
  end

  test "does nothing when there are no pending respondents" do
    survey = insert(:survey, %{schedule: Schedule.always(), state: "running"})
    insert(:respondent, survey: survey, state: "active")

    Broker.handle_info(:poll, nil)

    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"
  end

  test "set the respondent as completed when the questionnaire is empty" do
    [_, _, _, respondent, _] = create_running_survey_with_channel_and_respondent([])

    Broker.handle_info(:poll, nil)

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "completed"
  end

  test "adds a single disposition-changed survey-log-entry when respondent finishes and disposition was already completed" do
    [survey, _group, _test_channel, respondent, _phone_number] = create_running_survey_with_channel_and_respondent(@completed_flag_step_after_multiple_choice)

    {:ok, logger} = SurveyLogger.start_link
    {:ok, broker} = Broker.start_link
    Broker.poll

    respondent = Repo.get(Respondent, respondent.id)
    Broker.delivery_confirm(respondent, "Do you exercise?")

    Broker.sync_step(respondent, Flow.Message.reply("Yes"))

    :ok = logger |> GenServer.stop
    assert [do_you_exercise, disposition_changed_to_contacted, do_exercise, disposition_changed_to_started, disposition_changed_to_completed, thank_you] = (respondent |> Repo.preload(:survey_log_entries)).survey_log_entries

    assert do_you_exercise.survey_id == survey.id
    assert do_you_exercise.action_data == "Do you exercise?"
    assert do_you_exercise.action_type == "prompt"
    assert do_you_exercise.disposition == "queued"

    assert disposition_changed_to_contacted.survey_id == survey.id
    assert disposition_changed_to_contacted.action_data == "Contacted"
    assert disposition_changed_to_contacted.action_type == "disposition changed"
    assert disposition_changed_to_contacted.disposition == "queued"

    assert do_exercise.survey_id == survey.id
    assert do_exercise.action_data == "Yes"
    assert do_exercise.action_type == "response"
    assert do_exercise.disposition == "contacted"

    assert disposition_changed_to_started.survey_id == survey.id
    assert disposition_changed_to_started.action_data == "Started"
    assert disposition_changed_to_started.action_type == "disposition changed"
    assert disposition_changed_to_started.disposition == "contacted"

    assert disposition_changed_to_completed.survey_id == survey.id
    assert disposition_changed_to_completed.action_data == "Completed"
    assert disposition_changed_to_completed.action_type == "disposition changed"
    assert disposition_changed_to_completed.disposition == "started"

    assert thank_you.survey_id == survey.id
    assert thank_you.action_data == "Thank you"
    assert thank_you.action_type == "prompt"
    assert thank_you.disposition == "completed"

    :ok = broker |> GenServer.stop
  end

  test "set the respondent as completed (disposition) when the questionnaire is empty" do
    [_, _, _, respondent, _] = create_running_survey_with_channel_and_respondent([])

    Broker.handle_info(:poll, nil)

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.disposition == "completed"
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

  test "don't set the respondent as ineligible (disposition) if disposition is interim partial" do
    [_, _, _, respondent, _] =
      create_running_survey_with_channel_and_respondent(@invalid_ineligible_after_partial_steps)

    {:ok, _} = Broker.start_link

    Broker.handle_info(:poll, nil)

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.disposition == "interim partial"

    reply = Broker.sync_step(respondent, Flow.Message.reply("Yes"))
    assert {:reply, ReplyHelper.simple("Is this the last question?")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.disposition == "interim partial"
    assert respondent.effective_modes == ["sms"]
  end

  test "don't set the respondent as ineligible (disposition) if disposition is completed" do
    [_, _, _, respondent, _] = create_running_survey_with_channel_and_respondent(@completed_step ++ @ineligible_step)

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

  test "changes the respondent state from pending to running if neccessary" do
    [survey, _, _, respondent, _] = create_running_survey_with_channel_and_respondent()

    Broker.handle_info(:poll, nil)

    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"
    updated_respondent = Repo.get(Respondent, respondent.id)
    assert updated_respondent.state == "active"

    now = Timex.now
    interval = Interval.new(from: Timex.shift(now, minutes: 9), until: Timex.shift(now, minutes: 11), step: [seconds: 1])
    assert updated_respondent.timeout_at in interval
  end

  test "changes the respondent disposition from registered to queued" do
    [survey, _, _, respondent, _] = create_running_survey_with_channel_and_respondent()

    Broker.handle_info(:poll, nil)

    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"
    updated_respondent = Repo.get(Respondent, respondent.id)
    assert updated_respondent.disposition == "queued"
  end

  test "changes the respondent disposition from queued to contacted on delivery confirm (SMS)" do
    [_survey, _group, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent()

    {:ok, broker} = Broker.start_link
    Broker.poll

    assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.disposition == "queued"

    Broker.delivery_confirm(respondent, "Do you smoke?")

    updated_respondent = Repo.get(Respondent, respondent.id)
    assert updated_respondent.state == "active"
    assert updated_respondent.disposition == "contacted"

    :ok = broker |> GenServer.stop
  end

  test "changes the respondent disposition from queued to contacted on answer (IVR)" do
    [_survey, _group, _test_channel, respondent, _phone_number] = create_running_survey_with_channel_and_respondent(@dummy_steps, "ivr")

    {:ok, broker} = Broker.start_link
    Broker.poll

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.disposition == "queued"

    reply = Broker.sync_step(respondent, Flow.Message.answer())
    assert {:reply, ReplyHelper.ivr("Do you smoke?", "Do you smoke? Press 8 for YES, 9 for NO")} = reply

    updated_respondent = Repo.get(Respondent, respondent.id)
    assert updated_respondent.state == "active"
    assert updated_respondent.disposition == "contacted"

    :ok = broker |> GenServer.stop
  end

  test "changes the respondent disposition from contacted to started on first answer received" do
    [_survey, _group, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent()

    {:ok, broker} = Broker.start_link
    Broker.poll

    assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.disposition == "queued"

    Broker.delivery_confirm(respondent, "Do you smoke?")

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"
    assert respondent.disposition == "contacted"

    Broker.sync_step(respondent, Flow.Message.reply("Yes"))

    updated_respondent = Repo.get(Respondent, respondent.id)
    assert updated_respondent.state == "active"
    assert updated_respondent.disposition == "started"

    :ok = broker |> GenServer.stop
  end

  test "set timeout_at according to retries if they're present" do
    [survey, _, _, respondent, _] = create_running_survey_with_channel_and_respondent()
    survey |> Survey.changeset(%{sms_retry_configuration: "2m"}) |> Repo.update!

    {:ok, _} = Broker.start_link
    Broker.handle_info(:poll, nil)
    %Respondent{ timeout_at: timeout_at} = respondent = Repo.get(Respondent, respondent.id)
    Broker.sync_step(respondent, Flow.Message.reply("Yes"))

    retry_stat_filter = %{attempt: 1, mode: "sms", survey_id: survey.id}
    assert 1 == put_retry_time(retry_stat_filter, timeout_at) |> RetryStat.count

    updated_respondent = Repo.get(Respondent, respondent.id)
    assert updated_respondent.state == "active"

    now = Timex.now
    interval = Interval.new(from: Timex.shift(now, minutes: 1), until: Timex.shift(now, minutes: 3), step: [seconds: 1])
    assert updated_respondent.timeout_at in interval
  end

  test "set timeout_at according to retries, taking survey schedule into account" do
    [survey, _, _, respondent, _] = create_running_survey_with_channel_and_respondent()

    {:ok, _} = Broker.start_link
    Broker.handle_info(:poll, nil)

    survey |> Survey.changeset(%{sms_retry_configuration: "1d", schedule: Map.merge(Schedule.always(), %{day_of_week: day_after_tomorrow_schedule_day_of_week()})}) |> Repo.update!

    respondent = Repo.get(Respondent, respondent.id)
    Broker.sync_step(respondent, Flow.Message.reply("Yes"))

    updated_respondent = Repo.get(Respondent, respondent.id)
    assert updated_respondent.state == "active"

    {erl_date, _} = Timex.now |> Timex.shift(days: 2) |> Timex.to_erl
    time = Timex.Timezone.resolve("Etc/UTC", {erl_date, {0, 0, 0}})
    assert updated_respondent.timeout_at == time
  end

  test "retry respondent (SMS mode)" do
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

  test "retry respondent (mobileweb mode)" do
    [survey, _group, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent(@mobileweb_dummy_steps, "mobileweb")
    survey |> Survey.changeset(%{mobileweb_retry_configuration: "10m"}) |> Repo.update

    {:ok, broker} = Broker.start_link
    Broker.poll

    assert_receive [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _, ReplyHelper.simple("Contact", message)]
    assert message == "Please enter #{Routes.mobile_survey_url(Ask.Endpoint, :index, respondent.id, token: Respondent.token(respondent.id))}"

    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.stats.attempts["mobileweb"] == 1
    assert respondent.state == "active"

    # Set for immediate timeout
    %Respondent{ timeout_at: timeout_at} = respondent = Repo.get!(Respondent, respondent.id)

    retry_stat_filter = %{attempt: 1, mode: "mobileweb", survey_id: survey.id} |> put_retry_time(timeout_at)
    assert 1 == retry_stat_filter |> RetryStat.count

    timeout_at = Timex.now |> Timex.shift(minutes: -1)

    Respondent.changeset(respondent, %{timeout_at: timeout_at}) |> Repo.update

    retry_stat_filter = retry_stat_filter |> put_retry_time(timeout_at)
    RetryStat.add!(retry_stat_filter)

    # Second poll, retry the question
    Broker.poll
    refute_received [:setup, _, _, _, _]
    assert_receive [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _, ReplyHelper.simple("Contact", message)]
    assert message == "Please enter #{Routes.mobile_survey_url(Ask.Endpoint, :index, respondent.id, token: Respondent.token(respondent.id))}"

    assert 0 == RetryStat.count(retry_stat_filter)

    # Set for immediate timeout
    %Respondent{ timeout_at: timeout_at} = respondent = Repo.get!(Respondent, respondent.id)

    retry_stat_filter = %{attempt: 2, mode: "mobileweb", survey_id: survey.id} |> put_retry_time(timeout_at)
    assert 1 == retry_stat_filter |> RetryStat.count

    timeout_at = Timex.now |> Timex.shift(minutes: -1)

    Respondent.changeset(respondent, %{timeout_at: timeout_at}) |> Repo.update

    retry_stat_filter = retry_stat_filter |> put_retry_time(timeout_at)
    RetryStat.add!(retry_stat_filter)

    # Third poll, this time it should stall
    Broker.poll

    assert 0 == RetryStat.count(retry_stat_filter)

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "stalled"
    refute respondent.timeout_at

    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"

    :ok = broker |> GenServer.stop
  end

  test "respondent answers after stalled with active survey" do
    [survey, _group, test_channel, _respondent, phone_number] = create_running_survey_with_channel_and_respondent()

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
    assert respondent.state == "stalled"
    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"

    reply = Broker.sync_step(respondent, Flow.Message.reply("Yes"))
    respondent = Repo.get(Respondent, respondent.id) |> Repo.preload(:responses)
    assert {:reply, ReplyHelper.simple("Do you exercise", "Do you exercise? Reply 1 for YES, 2 for NO")} = reply
    assert survey.state == "running"
    assert respondent.state == "active"
    assert hd(respondent.responses).value == "Yes"
  end

  test "mark stalled respondent as failed after 8 hours" do
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

  test "mark disposition as partial" do
    [survey, _group, test_channel, _respondent, phone_number] = create_running_survey_with_channel_and_respondent(@flag_steps)

    {:ok, broker} = Broker.start_link
    {:ok, logger} = SurveyLogger.start_link

    # First poll, activate the respondent
    Broker.handle_info(:poll, nil)
    assert_received [:setup, ^test_channel, respondent = %Respondent{sanitized_phone_number: ^phone_number}, token]
    assert_received [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Do you exercise?", "Do you exercise? Reply 1 for YES, 2 for NO")]

    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"

    Broker.delivery_confirm(respondent, "Do you exercise?")

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"
    assert respondent.disposition == "interim partial"
    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"

    histories = RespondentDispositionHistory |> Repo.all
    assert length(histories) == 2

    history = histories |> Enum.take(-1) |> hd
    assert history.respondent_id == respondent.id
    assert history.disposition == "interim partial"
    assert history.mode == "sms"

    :ok = logger |> GenServer.stop

    [disposition_changed_to_interim_partial, do_you_exercise] = (respondent |> Repo.preload(:survey_log_entries)).survey_log_entries

    assert disposition_changed_to_interim_partial.survey_id == survey.id
    assert disposition_changed_to_interim_partial.action_data == "Interim partial"
    assert disposition_changed_to_interim_partial.action_type == "disposition changed"
    assert disposition_changed_to_interim_partial.disposition == "queued"

    assert do_you_exercise.survey_id == survey.id
    assert do_you_exercise.action_data == "Do you exercise?"
    assert do_you_exercise.action_type == "prompt"
    assert do_you_exercise.disposition == "interim partial"

    :ok = broker |> GenServer.stop
  end

  test "mark disposition as ineligible on end" do
    [_survey, _group, test_channel, _respondent, phone_number] = create_running_survey_with_channel_and_respondent(@flag_steps_ineligible_skip_logic)

    {:ok, _} = Broker.start_link

    # First poll, activate the respondent
    Broker.handle_info(:poll, nil)
    assert_received [:setup, ^test_channel, respondent = %Respondent{sanitized_phone_number: ^phone_number}, token]
    assert_received [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Do you exercise?", "Do you exercise? Reply 1 for YES, 2 for NO")]

    respondent = Repo.get!(Respondent, respondent.id)
    Broker.delivery_confirm(respondent, "Do you exercise?")
    Broker.sync_step(respondent, Flow.Message.reply("Yes"))

    respondent = Repo.get!(Respondent, respondent.id)
    assert respondent.state == "completed"
    assert respondent.disposition == "ineligible"

    histories = RespondentDispositionHistory |> Repo.all
    assert length(histories) == 4

    history = histories |> Enum.take(-1) |> hd
    assert history.respondent_id == respondent.id
    assert history.disposition == "ineligible"
  end

  test "mark disposition as refused on end" do
    [survey, _group, test_channel, _respondent, phone_number] = create_running_survey_with_channel_and_respondent(@flag_steps_refused_skip_logic)

    {:ok, broker} = Broker.start_link
    {:ok, logger} = SurveyLogger.start_link

    # First poll, activate the respondent
    Broker.handle_info(:poll, nil)
    assert_received [:setup, ^test_channel, respondent = %Respondent{sanitized_phone_number: ^phone_number}, token]
    assert_received [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Do you exercise?", "Do you exercise? Reply 1 for YES, 2 for NO")]

    respondent = Repo.get!(Respondent, respondent.id)
    Broker.sync_step(respondent, Flow.Message.reply("Yes"))

    respondent = Repo.get!(Respondent, respondent.id)
    assert respondent.state == "completed"
    assert respondent.disposition == "refused"

    histories = RespondentDispositionHistory |> Repo.all
    assert length(histories) == 3

    history = histories |> Enum.take(-1) |> hd
    assert history.respondent_id == respondent.id
    assert history.disposition == "refused"

    :ok = logger |> GenServer.stop

    [do_exercise, disposition_changed_to_started, disposition_changed_to_refused, bye, thank_you] = (respondent |> Repo.preload(:survey_log_entries)).survey_log_entries

    assert do_exercise.survey_id == survey.id
    assert do_exercise.action_data == "Yes"
    assert do_exercise.action_type == "response"
    assert do_exercise.disposition == "queued"

    assert disposition_changed_to_started.survey_id == survey.id
    assert disposition_changed_to_started.action_data == "Started"
    assert disposition_changed_to_started.action_type == "disposition changed"
    assert disposition_changed_to_started.disposition == "queued"

    assert disposition_changed_to_refused.survey_id == survey.id
    assert disposition_changed_to_refused.action_data == "Refused"
    assert disposition_changed_to_refused.action_type == "disposition changed"
    assert disposition_changed_to_refused.disposition == "started"

    assert bye.survey_id == survey.id
    assert bye.action_data == "Bye"
    assert bye.action_type == "prompt"
    assert bye.disposition == "refused"

    assert thank_you.survey_id == survey.id
    assert thank_you.action_data == "Thank you"
    assert thank_you.action_type == "prompt"
    assert thank_you.disposition == "refused"

    :ok = broker |> GenServer.stop
  end

  test "mark disposition as refused and respondent as failed when the respondent sends 'STOP'" do
    [survey, _group, test_channel, _respondent, phone_number] = create_running_survey_with_channel_and_respondent(@flag_steps_refused_skip_logic)

    {:ok, _} = Broker.start_link
    {:ok, logger} = SurveyLogger.start_link

    # First poll, activate the respondent
    Broker.handle_info(:poll, nil)
    assert_received [:setup, ^test_channel, respondent = %Respondent{sanitized_phone_number: ^phone_number}, token]
    assert_received [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Do you exercise?", "Do you exercise? Reply 1 for YES, 2 for NO")]

    respondent = Repo.get!(Respondent, respondent.id)
    Broker.sync_step(respondent, Flow.Message.reply("StoP"))

    respondent = Repo.get!(Respondent, respondent.id)
    assert respondent.state == "failed"
    assert respondent.disposition == "refused"

    histories = RespondentDispositionHistory |> Repo.all
    assert length(histories) == 3

    history = histories |> Enum.take(-1) |> hd
    assert history.respondent_id == respondent.id
    assert history.disposition == "refused"

    :ok = logger |> GenServer.stop
    last_entry = ((respondent |> Repo.preload(:survey_log_entries)).survey_log_entries) |> Enum.at(-1)

    assert last_entry.survey_id == survey.id
    assert last_entry.action_data == "Refused"
    assert last_entry.action_type == "disposition changed"
    assert last_entry.disposition == "started"
  end

  test "mark disposition as completed when partial on end" do
    [_survey, _group, test_channel, _respondent, phone_number] = create_running_survey_with_channel_and_respondent(@flag_steps_partial_skip_logic)

    {:ok, _} = Broker.start_link

    # First poll, activate the respondent
    Broker.handle_info(:poll, nil)
    assert_received [:setup, ^test_channel, respondent = %Respondent{sanitized_phone_number: ^phone_number}, token]
    assert_received [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Do you exercise?", "Do you exercise? Reply 1 for YES, 2 for NO")]

    respondent = Repo.get!(Respondent, respondent.id)
    Broker.sync_step(respondent, Flow.Message.reply("Yes"))

    respondent = Repo.get!(Respondent, respondent.id)
    assert respondent.state == "completed"
    assert respondent.disposition == "completed"

    histories = RespondentDispositionHistory |> Repo.all
    assert length(histories) == 3

    history = histories |> Enum.take(-1) |> hd
    assert history.respondent_id == respondent.id
    assert history.disposition == "completed"
  end

  test "don't reset disposition after having set it" do
    [survey, _group, test_channel, _respondent, phone_number] = create_running_survey_with_channel_and_respondent(@flag_steps)

    {:ok, _} = Broker.start_link

    # First poll, activate the respondent
    Broker.handle_info(:poll, nil)
    assert_received [:setup, ^test_channel, respondent = %Respondent{sanitized_phone_number: ^phone_number}, token]
    assert_received [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Do you exercise?", "Do you exercise? Reply 1 for YES, 2 for NO")]

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"
    assert respondent.disposition == "interim partial"
    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"

    reply = Broker.sync_step(respondent, Flow.Message.reply("Yes"))

    assert {:reply, ReplyHelper.simple("Is this the last question?")} = reply

    respondent = Repo.get(Respondent, respondent.id) |> Repo.preload(:responses)
    assert survey.state == "running"
    assert respondent.state == "active"
    assert respondent.disposition == "interim partial"
    assert hd(respondent.responses).value == "Yes"
  end

  test "contacted respondents are marked as unresponsive after 8 hours" do
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

    Broker.delivery_confirm(respondent, "Do you smoke?")

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

  test "queued respondents are marked failed after 8 hours" do
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

  test "when the respondent does not reply anything 3 times, but there are retries left the state stays as active" do
    [survey, _, _, respondent, _] = create_running_survey_with_channel_and_respondent(@dummy_steps, "ivr")
    survey |> Survey.changeset(%{ivr_retry_configuration: "10m"}) |> Repo.update
    right_first_answer = "8"

    {:ok, broker} = Broker.start_link
    Broker.poll

    respondent = Repo.get(Respondent, respondent.id)

    Broker.sync_step(respondent, Flow.Message.answer())

    respondent = Repo.get(Respondent, respondent.id)

    Broker.sync_step(respondent, Flow.Message.reply(right_first_answer))

    respondent = Repo.get(Respondent, respondent.id)

    Broker.sync_step(respondent, Flow.Message.no_reply)

    respondent = Repo.get(Respondent, respondent.id)

    Broker.sync_step(respondent, Flow.Message.no_reply)

    respondent = Repo.get(Respondent, respondent.id)

    assert respondent.state       == "active"
    assert respondent.disposition == "started"

    Broker.sync_step(respondent, Flow.Message.no_reply)

    respondent = Repo.get(Respondent, respondent.id)

    assert respondent.state       == "active"
    assert respondent.disposition == "started"

    now = Timex.now
    interval = Interval.new(from: Timex.shift(now, minutes: 9), until: Timex.shift(now, minutes: 11), step: [seconds: 1])
    assert respondent.timeout_at in interval

    :ok = broker |> GenServer.stop
  end

  test "when the respondent does not reply anything 3 times or gives an incorrect answer, but there are retries left the state stays as active" do
    [survey, _, _, respondent, _] = create_running_survey_with_channel_and_respondent(@dummy_steps, "ivr")
    survey |> Survey.changeset(%{ivr_retry_configuration: "10m"}) |> Repo.update
    right_first_answer = "8"
    wrong_second_answer = "16"

    {:ok, broker} = Broker.start_link
    Broker.poll

    respondent = Repo.get(Respondent, respondent.id)

    Broker.sync_step(respondent, Flow.Message.answer())

    respondent = Repo.get(Respondent, respondent.id)

    Broker.sync_step(respondent, Flow.Message.reply(right_first_answer))

    respondent = Repo.get(Respondent, respondent.id)

    Broker.sync_step(respondent, Flow.Message.no_reply)

    respondent = Repo.get(Respondent, respondent.id)

    Broker.sync_step(respondent, Flow.Message.reply(wrong_second_answer))

    respondent = Repo.get(Respondent, respondent.id)

    Broker.sync_step(respondent, Flow.Message.no_reply)

    respondent = Repo.get(Respondent, respondent.id)

    assert respondent.state       == "active"
    assert respondent.disposition == "started"

    now = Timex.now
    interval = Interval.new(from: Timex.shift(now, minutes: 9), until: Timex.shift(now, minutes: 11), step: [seconds: 1])
    assert respondent.timeout_at in interval

    :ok = broker |> GenServer.stop
  end

  test "started respondents are marked as breakoff after 8 hours" do
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

    Broker.delivery_confirm(respondent, "Do you smoke?")

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"
    assert respondent.disposition == "contacted"

    respondent = Repo.get(Respondent, respondent.id)
    Broker.sync_step(respondent, Flow.Message.reply("yes"))

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"
    assert respondent.disposition == "started"

    Broker.delivery_confirm(respondent, "Do you exercise?")

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

  test "stalled respondents are marked as failed after survey completes but disposition is kept" do
    [survey, group, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent()
    second_respondent = insert(:respondent, survey: survey, respondent_group: group)
    Repo.update(survey |> change |> Survey.changeset(%{cutoff: 1}))

    {:ok, broker} = Broker.start_link
    Broker.poll

    assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"
    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"
    assert respondent.disposition == "queued"

    Broker.delivery_confirm(respondent, "Do you smoke?")

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"
    assert respondent.disposition == "contacted"

    respondent = Repo.get(Respondent, respondent.id)
    Broker.sync_step(respondent, Flow.Message.reply("yes"))

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"
    assert respondent.disposition == "started"

    Broker.delivery_confirm(respondent, "Do you exercise?")

    Respondent.changeset(respondent, %{timeout_at: Timex.now |> Timex.shift(minutes: -1)}) |> Repo.update
    Broker.handle_info(:poll, nil)

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "stalled"
    assert respondent.disposition == "started"

    second_respondent = Repo.get(Respondent, second_respondent.id)
    Repo.update(second_respondent |> change |> Respondent.changeset(%{state: "completed"}))

    Broker.handle_info(:poll, nil)

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "failed"
    assert respondent.disposition == "started"

    :ok = broker |> GenServer.stop
  end

  test "started respondents are marked as breakoff after all retries are met (IVR)" do
    [survey, _, _, respondent, _] = create_running_survey_with_channel_and_respondent(@dummy_steps, "ivr")

    {:ok, broker} = Broker.start_link
    {:ok, logger} = SurveyLogger.start_link
    Broker.poll

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"
    assert respondent.disposition == "queued"

    reply = Broker.sync_step(respondent, Flow.Message.answer())
    assert {:reply, ReplyHelper.ivr("Do you smoke?", "Do you smoke? Press 8 for YES, 9 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("9"))
    assert {:reply, ReplyHelper.ivr("Do you exercise", "Do you exercise? Press 1 for YES, 2 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"
    assert respondent.disposition == "started"

    Respondent.changeset(respondent, %{timeout_at: Timex.now |> Timex.shift(minutes: -1)}) |> Repo.update
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

  test "interim partial respondents are kept as partial after all retries are met (IVR)" do
    [survey, _, _, respondent, _] = create_running_survey_with_channel_and_respondent(@dummy_steps_with_flag, "ivr")

    {:ok, broker} = Broker.start_link
    {:ok, logger} = SurveyLogger.start_link
    Broker.poll

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"
    assert respondent.disposition == "queued"

    reply = Broker.sync_step(respondent, Flow.Message.answer())
    assert {:reply, ReplyHelper.ivr("Do you smoke?", "Do you smoke? Press 8 for YES, 9 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("9"))
    assert {:reply, ReplyHelper.ivr("Do you exercise", "Do you exercise? Press 1 for YES, 2 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"
    assert respondent.disposition == "interim partial"

    Respondent.changeset(respondent, %{timeout_at: Timex.now |> Timex.shift(minutes: -1)}) |> Repo.update
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

  test "interim partial respondents are kept as partial after 8 hours (SMS)" do
    [survey, _, _, respondent, _] = create_running_survey_with_channel_and_respondent(@flag_step_after_multiple_choice)

    {:ok, broker} = Broker.start_link
    {:ok, logger} = SurveyLogger.start_link
    Broker.poll

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"
    assert respondent.disposition == "queued"

    Broker.delivery_confirm(respondent, "Do you smoke?")

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"
    assert respondent.disposition == "contacted"

    respondent = Repo.get(Respondent, respondent.id)
    Broker.sync_step(respondent, Flow.Message.reply("Yes"))

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"
    assert respondent.disposition == "interim partial"

    Broker.delivery_confirm(respondent, "Do you exercise?")

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

  test "completed respondents are kept as completed after all retries are met (IVR)" do
    [_, _, _, respondent, _] = create_running_survey_with_channel_and_respondent(@dummy_steps_with_flag, "ivr")

    {:ok, broker} = Broker.start_link
    Broker.poll

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"
    assert respondent.disposition == "queued"

    reply = Broker.sync_step(respondent, Flow.Message.answer())
    assert {:reply, ReplyHelper.ivr("Do you smoke?", "Do you smoke? Press 8 for YES, 9 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("9"))
    assert {:reply, ReplyHelper.ivr("Do you exercise", "Do you exercise? Press 1 for YES, 2 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"
    assert respondent.disposition == "interim partial"

    _reply = Broker.sync_step(respondent, Flow.Message.reply("1"))

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"
    assert respondent.disposition == "completed"

    Respondent.changeset(respondent, %{timeout_at: Timex.now |> Timex.shift(minutes: -1)}) |> Repo.update
    Broker.handle_info(:poll, nil)

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "failed"
    assert respondent.disposition == "completed"

    :ok = broker |> GenServer.stop
  end

  test "contacted respondents are marked as unresponsive after all retries are met (IVR)" do
    [survey, _, _, respondent, _] = create_running_survey_with_channel_and_respondent(@dummy_steps, "ivr")

    {:ok, broker} = Broker.start_link
    {:ok, logger} = SurveyLogger.start_link
    Broker.poll

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"
    assert respondent.disposition == "queued"

    reply = Broker.sync_step(respondent, Flow.Message.answer())
    assert {:reply, ReplyHelper.ivr("Do you smoke?", "Do you smoke? Press 8 for YES, 9 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"
    assert respondent.disposition == "contacted"

    Respondent.changeset(respondent, %{timeout_at: Timex.now |> Timex.shift(minutes: -1)}) |> Repo.update
    Broker.handle_info(:poll, nil)

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "failed"
    assert respondent.disposition == "unresponsive"

    :ok = logger |> GenServer.stop
    last_entry = ((respondent |> Repo.preload(:survey_log_entries)).survey_log_entries |> Enum.at(-1))

    assert last_entry.survey_id == survey.id
    assert last_entry.action_data == "Unresponsive"
    assert last_entry.action_type == "disposition changed"
    assert last_entry.disposition == "contacted"

    :ok = broker |> GenServer.stop
  end

  test "logs a timeout for each retry in IVR" do
    [_, _, _, respondent, _] = create_running_survey_with_channel_and_respondent(@dummy_steps, "ivr")

    {:ok, broker} = Broker.start_link
    {:ok, logger} = SurveyLogger.start_link
    Broker.poll

    respondent = Repo.get(Respondent, respondent.id)
    Broker.sync_step(respondent, Flow.Message.answer())

    respondent = Repo.get(Respondent, respondent.id)
    Broker.sync_step(respondent, Flow.Message.no_reply, "ivr")
    respondent = Repo.get(Respondent, respondent.id)
    Broker.sync_step(respondent, Flow.Message.no_reply, "ivr")
    respondent = Repo.get(Respondent, respondent.id)
    Broker.sync_step(respondent, Flow.Message.no_reply, "ivr")

    :ok = logger |> GenServer.stop

    [{"contact", nc}, {"disposition changed", nd}, {"prompt", np}] = Repo.all(from s in SurveyLogEntry, select: {s.action_type, count("*")}, group_by: s.action_type)
    assert nc == 5
    assert np == 3
    assert nd == 2

    :ok = broker |> GenServer.stop
  end

  test "contacted respondents are marked as partial after all retries are met, not breakoff (#1036)" do
    [_, _, _, respondent, _] = create_running_survey_with_channel_and_respondent(@dummy_steps, "ivr")

    {:ok, broker} = Broker.start_link
    Broker.poll

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.answer())
    assert {:reply, ReplyHelper.ivr("Do you smoke?", "Do you smoke? Press 8 for YES, 9 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"
    assert respondent.disposition == "contacted"

    respondent
    |> Respondent.changeset(%{
      disposition: "interim partial",
      timeout_at: Timex.now |> Timex.shift(minutes: -1)
    })
    |> Repo.update!

    Broker.handle_info(:poll, nil)

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "failed"
    assert respondent.disposition == "partial"

    :ok = broker |> GenServer.stop
  end

  test "retry respondent (IVR mode)" do
    [survey, _group, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent(@dummy_steps, "ivr")
    survey |> Survey.changeset(%{ivr_retry_configuration: "10m"}) |> Repo.update

    # First poll, activate the respondent
    Broker.handle_info(:poll, nil)
    assert_received [:setup, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token]

    retry_stat_filter = %{attempt: 1, mode: "ivr", survey_id: survey.id, retry_time: ""}
    assert 1 == retry_stat_filter |> RetryStat.count

    # Set for immediate timeout
    respondent = Repo.get(Respondent, respondent.id)
    Respondent.changeset(respondent, %{timeout_at: Timex.now |> Timex.shift(minutes: -1)}) |> Repo.update

    # Second poll, retry the question
    Broker.handle_info(:poll, nil)
    assert_received [:setup, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token]

    assert 0 == RetryStat.count(retry_stat_filter)
    retry_stat_filter = %{attempt: 2, mode: "ivr", survey_id: survey.id, retry_time: ""}
    assert 1 == retry_stat_filter |> RetryStat.count

    # Set for immediate timeout
    respondent = Repo.get(Respondent, respondent.id)
    Respondent.changeset(respondent, %{timeout_at: Timex.now |> Timex.shift(minutes: -1)}) |> Repo.update

    # Third poll, this time it should fail
    Broker.handle_info(:poll, nil)

    assert 0 == RetryStat.count(retry_stat_filter)

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "failed"

    survey = Repo.get(Survey, survey.id)
    assert Survey.completed?(survey)
  end

  test "IVR no reply shouldn't change disposition to started (#1028)" do
    [_survey, _group, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent(@dummy_steps, "ivr")

    # First poll, activate the respondent
    Broker.handle_info(:poll, nil)
    assert_received [:setup, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token]

    respondent = Repo.get(Respondent, respondent.id)
    Broker.sync_step(respondent, Flow.Message.no_reply)

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.disposition == "queued"
  end

  test "fallback respondent (SMS => IVR)" do
    test_channel = TestChannel.new
    channel = insert(:channel, settings: test_channel |> TestChannel.settings, type: "sms")

    test_fallback_channel = TestChannel.new
    fallback_channel = insert(:channel, settings: test_fallback_channel |> TestChannel.settings, type: "ivr")

    quiz = insert(:questionnaire, steps: @dummy_steps)
    survey = insert(:survey, %{schedule: Schedule.always(), state: "running", questionnaires: [quiz], mode: [["sms", "ivr"]]})
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

    # Set for immediate timeout
    %Respondent{ timeout_at: timeout_at} = respondent = Repo.get(Respondent, respondent.id)

    retry_stat_filter = %{attempt: 1, mode: "sms", survey_id: survey.id} |> put_retry_time(timeout_at)
    assert 1 == retry_stat_filter |> RetryStat.count

    timeout_at = Timex.now |> Timex.shift(minutes: -1)

    Respondent.changeset(respondent, %{timeout_at: timeout_at}) |> Repo.update

    retry_stat_filter = retry_stat_filter |> put_retry_time(timeout_at)
    RetryStat.add!(retry_stat_filter)

    # Second poll, retry the question
    Broker.handle_info(:poll, nil)

    assert 0 == RetryStat.count(retry_stat_filter)

    refute_received [:setup, _, _, _, _]
    assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    # Set for immediate timeout
    %Respondent{ timeout_at: timeout_at} = respondent = Repo.get(Respondent, respondent.id)

    retry_stat_filter = %{attempt: 2, mode: "sms", survey_id: survey.id} |> put_retry_time(timeout_at)
    assert 1 == retry_stat_filter |> RetryStat.count

    timeout_at = Timex.now |> Timex.shift(minutes: -1)

    Respondent.changeset(respondent, %{timeout_at: timeout_at}) |> Repo.update

    retry_stat_filter = retry_stat_filter |> put_retry_time(timeout_at)
    RetryStat.add!(retry_stat_filter)

    # Third poll, retry the question
    Broker.handle_info(:poll, nil)
    refute_received [:setup, _, _, _, _]
    assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    assert 0 == RetryStat.count(retry_stat_filter)

    # Set for immediate timeout
    %Respondent{ timeout_at: timeout_at} = respondent = Repo.get(Respondent, respondent.id)

    retry_stat_filter = %{attempt: 3, mode: "sms", survey_id: survey.id} |> put_retry_time(timeout_at)
    assert 1 == retry_stat_filter |> RetryStat.count

    timeout_at = Timex.now |> Timex.shift(minutes: -1)

    Respondent.changeset(respondent, %{timeout_at: timeout_at}) |> Repo.update

    retry_stat_filter = retry_stat_filter |> put_retry_time(timeout_at)
    RetryStat.add!(retry_stat_filter)

    # Fourth poll, this time fallback to IVR channel
    Broker.handle_info(:poll, nil)
    assert_received [:setup, ^test_fallback_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token]

    assert 0 == RetryStat.count(retry_stat_filter)
  end

  defp put_retry_time(filter, timeout_at), do: filter |> Map.put(:retry_time, Timex.format!(timeout_at, "%Y%0m%0d%H%M", :strftime))

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

  test "should not keep setting pending to actives when cutoff is reached" do
    [survey, group, _, _, _] = create_running_survey_with_channel_and_respondent()
    create_several_respondents(survey, group, 20)

    Repo.update(survey |> change |> Survey.changeset(%{cutoff: 1}))

    Broker.handle_info(:poll, nil)

    survey = Repo.get(Survey, survey.id)
    assert_respondents_by_state(survey, 1, 20)

    r = Repo.all(from r in Respondent, where: r.state == "active") |> hd
    Repo.update(r |> change |> Respondent.changeset(%{state: "completed"}))

    Broker.handle_info(:poll, nil)

    assert_respondents_by_state(survey, 0, 20)
    assert survey.state == "running"
  end

  test "marks survey as complete when the cutoff is reached and actives become stalled" do
    [survey, group, _, _, _] = create_running_survey_with_channel_and_respondent()
    create_several_respondents(survey, group, 20)

    Repo.update(survey |> change |> Survey.changeset(%{cutoff: 1}))

    Broker.handle_info(:poll, nil)

    survey = Repo.get(Survey, survey.id)
    assert_respondents_by_state(survey, 1, 20)

    r = Repo.all(from r in Respondent, where: r.state == "active") |> hd
    Repo.update(r |> change |> Respondent.changeset(%{state: "completed"}))

    Repo.all(from r in Respondent, where: r.state == "active")
    |> Enum.map(fn respondent ->
      Repo.update(respondent |> change |> Respondent.changeset(%{state: "stalled"}))
    end)

    Broker.handle_info(:poll, nil)

    survey = Repo.get(Survey, survey.id)

    assert_respondents_by_state(survey, 0, 20)
    assert Survey.completed?(survey)
  end

  test "marks survey as complete when the cutoff is reached and actives become failed" do
    [survey, group, _, _, _] = create_running_survey_with_channel_and_respondent()
    create_several_respondents(survey, group, 20)

    Repo.update(survey |> change |> Survey.changeset(%{cutoff: 1}))

    Broker.handle_info(:poll, nil)

    survey = Repo.get(Survey, survey.id)
    assert_respondents_by_state(survey, 1, 20)

    r = Repo.all(from r in Respondent, where: r.state == "active") |> hd
    Repo.update(r |> change |> Respondent.changeset(%{state: "completed"}))

    Repo.all(from r in Respondent, where: r.state == "active")
    |> Enum.map(fn respondent ->
      Repo.update(respondent |> change |> Respondent.changeset(%{state: "failed"}))
    end)

    Broker.handle_info(:poll, nil)

    survey = Repo.get(Survey, survey.id)

    assert_respondents_by_state(survey, 0, 20)
    assert Survey.completed?(survey)
  end

  test "marks the survey as completed when the cutoff is reached and actives become completed" do
    [survey, group, _, _, _] = create_running_survey_with_channel_and_respondent()
    create_several_respondents(survey, group, 20)

    Repo.update(survey |> change |> Survey.changeset(%{cutoff: 6}))

    Broker.handle_info(:poll, nil)

    survey = Repo.get(Survey, survey.id)

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

    survey = Repo.get(Survey, survey.id)
    assert Survey.completed?(survey)
  end

  test "marks the survey as completed when all the quotas are reached and actives become completed" do
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
    |> Survey.changeset(%{quotas: quotas})
    |> Repo.update!

    qb1 = (from q in QuotaBucket, where: q.quota == 1) |> Repo.one
    qb2 = (from q in QuotaBucket, where: q.quota == 2) |> Repo.one
    qb3 = (from q in QuotaBucket, where: q.quota == 3) |> Repo.one
    qb4 = (from q in QuotaBucket, where: q.quota == 4) |> Repo.one

    Broker.handle_info(:poll, nil)

    # In the beginning it shouldn't be completed
    survey = Survey |> Repo.get(survey.id)
    assert survey.state == "running"

    # Not yet completed: missing fourth bucket
    qb1 |> QuotaBucket.changeset(%{count: 1}) |> Repo.update!
    qb2 |> QuotaBucket.changeset(%{count: 2}) |> Repo.update!
    qb3 |> QuotaBucket.changeset(%{count: 3}) |> Repo.update!
    qb4 |> QuotaBucket.changeset(%{count: 3}) |> Repo.update!
    Broker.handle_info(:poll, nil)

    survey = Survey |> Repo.get(survey.id)
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

    survey = Survey |> Repo.get(survey.id)
    assert Survey.completed?(survey)
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
    |> Survey.changeset(%{quotas: quotas})
    |> Repo.update!

    qb1 = (from q in QuotaBucket, where: q.quota == 1) |> Repo.one
    qb2 = (from q in QuotaBucket, where: q.quota == 2) |> Repo.one
    qb3 = (from q in QuotaBucket, where: q.quota == 3) |> Repo.one
    qb4 = (from q in QuotaBucket, where: q.quota == 4) |> Repo.one

    Broker.handle_info(:poll, nil)

    survey = Survey |> Repo.get(survey.id)
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

    survey = Survey |> Repo.get(survey.id)
    assert_respondents_by_state(survey, 5, 11)
  end

  test "marks the survey as completed when all the quotas are reached and actives become stalled" do
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
    |> Survey.changeset(%{quotas: quotas})
    |> Repo.update!

    qb1 = (from q in QuotaBucket, where: q.quota == 1) |> Repo.one
    qb2 = (from q in QuotaBucket, where: q.quota == 2) |> Repo.one
    qb3 = (from q in QuotaBucket, where: q.quota == 3) |> Repo.one
    qb4 = (from q in QuotaBucket, where: q.quota == 4) |> Repo.one

    Broker.handle_info(:poll, nil)

    survey = Survey |> Repo.get(survey.id)
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

    survey = Survey |> Repo.get(survey.id)
    assert_respondents_by_state(survey, 0, 11)
    assert Survey.completed?(survey)
  end

  test "marks the survey as completed when all the quotas are reached and actives become failed" do
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
    |> Survey.changeset(%{quotas: quotas})
    |> Repo.update!

    qb1 = (from q in QuotaBucket, where: q.quota == 1) |> Repo.one
    qb2 = (from q in QuotaBucket, where: q.quota == 2) |> Repo.one
    qb3 = (from q in QuotaBucket, where: q.quota == 3) |> Repo.one
    qb4 = (from q in QuotaBucket, where: q.quota == 4) |> Repo.one

    Broker.handle_info(:poll, nil)

    survey = Survey |> Repo.get(survey.id)
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

    survey = Survey |> Repo.get(survey.id)
    assert_respondents_by_state(survey, 0, 11)
    assert Survey.completed?(survey)
  end

  test "always keeps batch_size number of respondents running" do
    [survey, group, _, _, _] = create_running_survey_with_channel_and_respondent()
    create_several_respondents(survey, group, 20)

    Broker.handle_info(:poll, nil)

    survey = Repo.get(Survey, survey.id)

    assert survey.state == "running"

    assert_respondents_by_state(survey, 10, 11)

    active_respondent = Repo.all(from r in Respondent, where: r.state == "active")
    |> Enum.at(0)

    Repo.update(active_respondent |> change |> Respondent.changeset(%{state: "failed"}))

    assert_respondents_by_state(survey, 9, 11)

    Broker.handle_info(:poll, nil)

    assert_respondents_by_state(survey, 10, 10)
  end

  test "when a survey has any target of completed respondents the batch size depends on the success rate" do
    [survey, group, _, _, _] = create_running_survey_with_channel_and_respondent()
    create_several_respondents(survey, group, 200)

    Repo.update(survey |> change |> Survey.changeset(%{cutoff: 50}))

    Broker.handle_info(:poll, nil)
    assert_respondents_by_state(survey, 50, 151)

    mark_n_active_respondents_as("failed", 20)
    mark_n_active_respondents_as("completed", 30)
    Broker.handle_info(:poll, nil)
    assert_respondents_by_state(survey, 26, 125)

    # since all the previous ones failed the success rate decreases
    # and the batch size increases
    mark_n_active_respondents_as("failed", 26)
    Broker.handle_info(:poll, nil)
    assert_respondents_by_state(survey, 31, 94)
  end

  test "" do
    [survey, group, _, _, _] = create_running_survey_with_channel_and_respondent()
    create_several_respondents(survey, group, 10)
    survey |> Survey.changeset(%{quota_vars: ["gender"]}) |> Repo.update
    insert(:quota_bucket, survey: survey, condition: %{gender: "male"}, quota: 1, count: 0)

    Broker.handle_info(:poll, nil)
    assert_respondents_by_state(survey, 1, 10)

    mark_n_active_respondents_as("completed", 1)

    Broker.handle_info(:poll, nil)
    assert_respondents_by_state(survey, 1, 9)
  end

  test "continue polling respondents when one of the quotas was exceeded " do
    [survey, group, _, _, _] = create_running_survey_with_channel_and_respondent()
    create_several_respondents(survey, group, 10)
    survey |> Survey.changeset(%{quota_vars: ["gender"]}) |> Repo.update
    insert(:quota_bucket, survey: survey, condition: %{gender: "male"}, quota: 1, count: 2)
    insert(:quota_bucket, survey: survey, condition: %{gender: "female"}, quota: 1, count: 0)

    Broker.handle_info(:poll, nil)
    assert_respondents_by_state(survey, 1, 10)
  end

  test "changes running survey state to 'completed' when there are no more running respondents" do
    [survey, _, _, respondent, _] = create_running_survey_with_channel_and_respondent()

    Broker.handle_info(:poll, nil)

    assert_respondents_by_state(survey, 1, 0)

    respondent = Repo.get(Respondent, respondent.id)
    Repo.update(respondent |> change |> Respondent.changeset(%{state: "failed"}))

    Broker.handle_info(:poll, nil)

    survey = Repo.get(Survey, survey.id)
    assert Survey.completed?(survey)
  end

  test "respondent flow via sms" do
    [survey, _group, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent()

    {:ok, logger} = SurveyLogger.start_link
    {:ok, broker} = Broker.start_link
    Broker.poll

    assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"

    Broker.delivery_confirm(respondent, "Do you smoke?")

    reply = Broker.sync_step(respondent, Flow.Message.reply("Yes"))
    assert {:reply, ReplyHelper.simple("Do you exercise", "Do you exercise? Reply 1 for YES, 2 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    Broker.delivery_confirm(respondent, "Do you exercise")

    reply = Broker.sync_step(respondent, Flow.Message.reply("Yes"))
    assert {:reply, ReplyHelper.simple("Which is the second perfect number?", "Which is the second perfect number??")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    Broker.delivery_confirm(respondent, "Which is the second perfect number?")

    reply = Broker.sync_step(respondent, Flow.Message.reply("99"))
    assert {:reply, ReplyHelper.simple("What's the number of this question?", "What's the number of this question??")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    Broker.delivery_confirm(respondent, "What's the number of this question?")

    reply = Broker.sync_step(respondent, Flow.Message.reply("11"))
    assert {:end, {:reply, ReplyHelper.simple("Thank you", "Thanks for completing this survey")}} = reply

    now = Timex.now
    interval = Interval.new(from: Timex.shift(now, seconds: -5), until: Timex.shift(now, seconds: 5), step: [seconds: 1])

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "completed"
    assert respondent.session == nil
    assert respondent.completed_at in interval

    :ok = logger |> GenServer.stop

    assert [do_you_smoke, disposition_changed_to_contacted, do_smoke, disposition_changed_to_started, do_you_exercise, do_exercise, second_perfect_number, ninety_nine, question_number, eleven, thank_you, disposition_changed_to_completed] = (respondent |> Repo.preload(:survey_log_entries)).survey_log_entries

    assert do_you_smoke.survey_id == survey.id
    assert do_you_smoke.action_data == "Do you smoke?"
    assert do_you_smoke.action_type == "prompt"
    assert do_you_smoke.disposition == "queued"

    assert disposition_changed_to_contacted.survey_id == survey.id
    assert disposition_changed_to_contacted.action_data == "Contacted"
    assert disposition_changed_to_contacted.action_type == "disposition changed"
    assert disposition_changed_to_contacted.disposition == "queued"

    assert do_smoke.survey_id == survey.id
    assert do_smoke.action_data == "Yes"
    assert do_smoke.action_type == "response"
    assert do_smoke.disposition == "contacted"

    assert disposition_changed_to_started.survey_id == survey.id
    assert disposition_changed_to_started.action_data == "Started"
    assert disposition_changed_to_started.action_type == "disposition changed"
    assert disposition_changed_to_started.disposition == "contacted"

    assert do_you_exercise.survey_id == survey.id
    assert do_you_exercise.action_data == "Do you exercise"
    assert do_you_exercise.action_type == "prompt"
    assert do_you_exercise.disposition == "started"

    assert do_exercise.survey_id == survey.id
    assert do_exercise.action_data == "Yes"
    assert do_exercise.action_type == "response"
    assert do_exercise.disposition == "started"

    assert second_perfect_number.survey_id == survey.id
    assert second_perfect_number.action_data == "Which is the second perfect number?"
    assert second_perfect_number.action_type == "prompt"
    assert second_perfect_number.disposition == "started"

    assert ninety_nine.survey_id == survey.id
    assert ninety_nine.action_data == "99"
    assert ninety_nine.action_type == "response"
    assert ninety_nine.disposition == "started"

    assert question_number.survey_id == survey.id
    assert question_number.action_data == "What's the number of this question?"
    assert question_number.action_type == "prompt"
    assert question_number.disposition == "started"

    assert eleven.survey_id == survey.id
    assert eleven.action_data == "11"
    assert eleven.action_type == "response"
    assert eleven.disposition == "started"

    assert thank_you.survey_id == survey.id
    assert thank_you.action_data == "Thank you"
    assert thank_you.action_type == "prompt"
    assert thank_you.disposition == "started"

    assert disposition_changed_to_completed.survey_id == survey.id
    assert disposition_changed_to_completed.action_data == "Completed"
    assert disposition_changed_to_completed.action_type == "disposition changed"
    assert disposition_changed_to_completed.disposition == "started"

    :ok = broker |> GenServer.stop
  end

  test "respondent flow via ivr" do
    [survey, _group, _test_channel, respondent, _phone_number] = create_running_survey_with_channel_and_respondent(@dummy_steps, "ivr")

    {:ok, logger} = SurveyLogger.start_link
    {:ok, broker} = Broker.start_link
    Broker.poll

    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"

    reply = Broker.sync_step(respondent, Flow.Message.answer())
    assert {:reply, ReplyHelper.ivr("Do you smoke?", "Do you smoke? Press 8 for YES, 9 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("9"))
    assert {:reply, ReplyHelper.ivr("Do you exercise", "Do you exercise? Press 1 for YES, 2 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("1"))
    assert {:reply, ReplyHelper.ivr("Which is the second perfect number?", "Which is the second perfect number")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("99"))
    assert {:reply, ReplyHelper.ivr("What's the number of this question?", "What's the number of this question")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("11"))
    assert {:end, {:reply, ReplyHelper.ivr("Thank you", "Thanks for completing this survey (ivr)")}} = reply

    now = Timex.now
    interval = Interval.new(from: Timex.shift(now, seconds: -5), until: Timex.shift(now, seconds: 5), step: [seconds: 1])

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "completed"
    assert respondent.session == nil
    assert respondent.completed_at in interval

    :ok = logger |> GenServer.stop

    assert [enqueueing, answer, disposition_changed_to_contacted, do_you_smoke, do_smoke, disposition_changed_to_started, do_you_exercise, do_exercise, second_perfect_number, ninety_nine, question_number, eleven, thank_you, disposition_changed_to_completed] = (respondent |> Repo.preload(:survey_log_entries)).survey_log_entries

    assert enqueueing.survey_id == survey.id
    assert enqueueing.action_data == "Enqueueing call"
    assert enqueueing.action_type == "contact"
    assert enqueueing.disposition == "queued"

    assert answer.survey_id == survey.id
    assert answer.action_data == "Answer"
    assert answer.action_type == "contact"
    assert answer.disposition == "queued"

    assert disposition_changed_to_contacted.survey_id == survey.id
    assert disposition_changed_to_contacted.action_data == "Contacted"
    assert disposition_changed_to_contacted.action_type == "disposition changed"
    assert disposition_changed_to_contacted.disposition == "queued"

    assert do_you_smoke.survey_id == survey.id
    assert do_you_smoke.action_data == "Do you smoke?"
    assert do_you_smoke.action_type == "prompt"
    assert do_you_smoke.disposition == "contacted"

    assert do_smoke.survey_id == survey.id
    assert do_smoke.action_data == "9"
    assert do_smoke.action_type == "response"
    assert do_smoke.disposition == "contacted"

    assert disposition_changed_to_started.survey_id == survey.id
    assert disposition_changed_to_started.action_data == "Started"
    assert disposition_changed_to_started.action_type == "disposition changed"
    assert disposition_changed_to_started.disposition == "contacted"

    assert do_you_exercise.survey_id == survey.id
    assert do_you_exercise.action_data == "Do you exercise"
    assert do_you_exercise.action_type == "prompt"
    assert do_you_exercise.disposition == "started"

    assert do_exercise.survey_id == survey.id
    assert do_exercise.action_data == "1"
    assert do_exercise.action_type == "response"
    assert do_exercise.disposition == "started"

    assert second_perfect_number.survey_id == survey.id
    assert second_perfect_number.action_data == "Which is the second perfect number?"
    assert second_perfect_number.action_type == "prompt"
    assert second_perfect_number.disposition == "started"

    assert ninety_nine.survey_id == survey.id
    assert ninety_nine.action_data == "99"
    assert ninety_nine.action_type == "response"
    assert ninety_nine.disposition == "started"

    assert question_number.survey_id == survey.id
    assert question_number.action_data == "What's the number of this question?"
    assert question_number.action_type == "prompt"
    assert question_number.disposition == "started"

    assert eleven.survey_id == survey.id
    assert eleven.action_data == "11"
    assert eleven.action_type == "response"
    assert eleven.disposition == "started"

    assert thank_you.survey_id == survey.id
    assert thank_you.action_data == "Thank you"
    assert thank_you.action_type == "prompt"
    assert thank_you.disposition == "started"

    assert disposition_changed_to_completed.survey_id == survey.id
    assert disposition_changed_to_completed.action_data == "Completed"
    assert disposition_changed_to_completed.action_type == "disposition changed"
    assert disposition_changed_to_completed.disposition == "started"

    :ok = broker |> GenServer.stop
  end

  test "respondent flow via mobileweb" do
    [survey, _group, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent(@mobileweb_dummy_steps, "mobileweb")

    {:ok, broker} = Broker.start_link
    {:ok, logger} = SurveyLogger.start_link
    Broker.poll

    assert_receive [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _, ReplyHelper.simple("Contact", message)]
    assert message == "Please enter #{Routes.mobile_survey_url(Ask.Endpoint, :index, respondent.id, token: Respondent.token(respondent.id))}"

    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"

    reply = Broker.sync_step(respondent, Flow.Message.answer())
    assert {:reply, ReplyHelper.simple("Let there be rock", "Welcome to the survey!")} = reply

    reply = Broker.sync_step(respondent, Flow.Message.answer())
    assert {:reply, ReplyHelper.simple("Let there be rock", "Welcome to the survey!")} = reply

    reply = Broker.sync_step(respondent, Flow.Message.answer())
    assert {:reply, ReplyHelper.simple("Let there be rock", "Welcome to the survey!")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply(""))
    assert {:reply, ReplyHelper.simple("Do you smoke?", "Do you smoke?")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("Yes"))
    assert {:reply, ReplyHelper.simple("Do you exercise", "Do you exercise?")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("Yes"))
    assert {:reply, ReplyHelper.simple("Which is the second perfect number?", "Which is the second perfect number??")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("99"))
    assert {:reply, ReplyHelper.simple("What's the number of this question?", "What's the number of this question??")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("11"))
    assert {:end, {:reply, ReplyHelper.simple("Thank you", "Thanks for completing this survey (mobileweb)")}} = reply

    now = Timex.now
    interval = Interval.new(from: Timex.shift(now, seconds: -5), until: Timex.shift(now, seconds: 5), step: [seconds: 1])

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "completed"
    assert respondent.session == nil
    assert respondent.completed_at in interval

    :ok = logger |> GenServer.stop

    last_entry = ((respondent |> Repo.preload(:survey_log_entries)).survey_log_entries) |> Enum.at(-1)

    assert last_entry.survey_id == survey.id
    assert last_entry.action_data == "Completed"
    assert last_entry.action_type == "disposition changed"
    assert last_entry.disposition == "interim partial"

    :ok = broker |> GenServer.stop
  end

  test "respondent flow via sms with an empty thank you message" do
    [survey, _group, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent(@dummy_steps)

    hd((survey |> Ask.Repo.preload(:questionnaires)).questionnaires)
    |> Questionnaire.changeset(%{
      settings: %{
        "error_message" => %{
          "en" => %{
            "sms" => "You have entered an invalid answer",
            "ivr" => %{
              "audio_source" => "tts",
              "text" => "You have entered an invalid answer (ivr)"
            }
          }
        },
        "thank_you_message" => %{
          "en" => %{
            "ivr" => %{
              "audio_source" => "tts",
              "text" => ""
            },
            "sms" => ""
          }
        }
      }
    })
    |> Repo.update!

    {:ok, logger} = SurveyLogger.start_link
    {:ok, broker} = Broker.start_link
    Broker.poll

    assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"

    Broker.delivery_confirm(respondent, "Do you smoke?")

    reply = Broker.sync_step(respondent, Flow.Message.reply("Yes"))
    assert {:reply, ReplyHelper.simple("Do you exercise", "Do you exercise? Reply 1 for YES, 2 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    Broker.delivery_confirm(respondent, "Do you exercise")

    reply = Broker.sync_step(respondent, Flow.Message.reply("Yes"))
    assert {:reply, ReplyHelper.simple("Which is the second perfect number?", "Which is the second perfect number??")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    Broker.delivery_confirm(respondent, "Which is the second perfect number?")

    reply = Broker.sync_step(respondent, Flow.Message.reply("99"))
    assert {:reply, ReplyHelper.simple("What's the number of this question?", "What's the number of this question??")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    Broker.delivery_confirm(respondent, "What's the number of this question?")

    reply = Broker.sync_step(respondent, Flow.Message.reply("11"))
    assert :end = reply

    now = Timex.now
    interval = Interval.new(from: Timex.shift(now, seconds: -5), until: Timex.shift(now, seconds: 5), step: [seconds: 1])

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "completed"
    assert respondent.session == nil
    assert respondent.completed_at in interval

    :ok = logger |> GenServer.stop

    assert [do_you_smoke, disposition_changed_to_contacted, do_smoke, disposition_changed_to_started, do_you_exercise, do_exercise, second_perfect_number, ninety_nine, question_number, eleven, disposition_changed_to_completed] = (respondent |> Repo.preload(:survey_log_entries)).survey_log_entries

    assert do_you_smoke.survey_id == survey.id
    assert do_you_smoke.action_data == "Do you smoke?"
    assert do_you_smoke.action_type == "prompt"
    assert do_you_smoke.disposition == "queued"

    assert disposition_changed_to_contacted.survey_id == survey.id
    assert disposition_changed_to_contacted.action_data == "Contacted"
    assert disposition_changed_to_contacted.action_type == "disposition changed"
    assert disposition_changed_to_contacted.disposition == "queued"

    assert do_smoke.survey_id == survey.id
    assert do_smoke.action_data == "Yes"
    assert do_smoke.action_type == "response"
    assert do_smoke.disposition == "contacted"

    assert disposition_changed_to_started.survey_id == survey.id
    assert disposition_changed_to_started.action_data == "Started"
    assert disposition_changed_to_started.action_type == "disposition changed"
    assert disposition_changed_to_started.disposition == "contacted"

    assert do_you_exercise.survey_id == survey.id
    assert do_you_exercise.action_data == "Do you exercise"
    assert do_you_exercise.action_type == "prompt"
    assert do_you_exercise.disposition == "started"

    assert do_exercise.survey_id == survey.id
    assert do_exercise.action_data == "Yes"
    assert do_exercise.action_type == "response"
    assert do_exercise.disposition == "started"

    assert second_perfect_number.survey_id == survey.id
    assert second_perfect_number.action_data == "Which is the second perfect number?"
    assert second_perfect_number.action_type == "prompt"
    assert second_perfect_number.disposition == "started"

    assert ninety_nine.survey_id == survey.id
    assert ninety_nine.action_data == "99"
    assert ninety_nine.action_type == "response"
    assert ninety_nine.disposition == "started"

    assert question_number.survey_id == survey.id
    assert question_number.action_data == "What's the number of this question?"
    assert question_number.action_type == "prompt"
    assert question_number.disposition == "started"

    assert eleven.survey_id == survey.id
    assert eleven.action_data == "11"
    assert eleven.action_type == "response"
    assert eleven.disposition == "started"

    assert disposition_changed_to_completed.survey_id == survey.id
    assert disposition_changed_to_completed.action_data == "Completed"
    assert disposition_changed_to_completed.action_type == "disposition changed"
    assert disposition_changed_to_completed.disposition == "started"

    :ok = broker |> GenServer.stop
  end

  test "respondent flow via sms with an empty thank you message and a final explanation" do
    [survey, _group, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent(
        @dummy_steps ++ [
          StepBuilder.explanation_step(
            id: "aaa",
            title: "Bye",
            prompt: StepBuilder.prompt(
              sms: StepBuilder.sms_prompt("This is the last question")
            ),
            skip_logic: nil
          )
        ]
      )

    hd((survey |> Ask.Repo.preload(:questionnaires)).questionnaires)
    |> Questionnaire.changeset(%{
      settings: %{
        "error_message" => %{
          "en" => %{
            "sms" => "You have entered an invalid answer",
            "ivr" => %{
              "audio_source" => "tts",
              "text" => "You have entered an invalid answer (ivr)"
            }
          }
        },
        "thank_you_message" => %{
          "en" => %{
            "ivr" => %{
              "audio_source" => "tts",
              "text" => ""
            },
            "sms" => ""
          }
        }
      }
    })
    |> Repo.update!

    {:ok, logger} = SurveyLogger.start_link
    {:ok, broker} = Broker.start_link
    Broker.poll

    assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"

    Broker.delivery_confirm(respondent, "Do you smoke?")

    reply = Broker.sync_step(respondent, Flow.Message.reply("Yes"))
    assert {:reply, ReplyHelper.simple("Do you exercise", "Do you exercise? Reply 1 for YES, 2 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    Broker.delivery_confirm(respondent, "Do you exercise")

    reply = Broker.sync_step(respondent, Flow.Message.reply("Yes"))
    assert {:reply, ReplyHelper.simple("Which is the second perfect number?", "Which is the second perfect number??")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    Broker.delivery_confirm(respondent, "Which is the second perfect number?")

    reply = Broker.sync_step(respondent, Flow.Message.reply("99"))
    assert {:reply, ReplyHelper.simple("What's the number of this question?", "What's the number of this question??")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    Broker.delivery_confirm(respondent, "What's the number of this question?")

    reply = Broker.sync_step(respondent, Flow.Message.reply("11"))
    assert {:end, {:reply, ReplyHelper.simple("Bye", "This is the last question")}} = reply

    now = Timex.now
    interval = Interval.new(from: Timex.shift(now, seconds: -5), until: Timex.shift(now, seconds: 5), step: [seconds: 1])

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "completed"
    assert respondent.session == nil
    assert respondent.completed_at in interval

    :ok = logger |> GenServer.stop

    assert [do_you_smoke, disposition_changed_to_contacted, do_smoke, disposition_changed_to_started, do_you_exercise, do_exercise, second_perfect_number, ninety_nine, question_number, eleven, bye, disposition_changed_to_completed] = (respondent |> Repo.preload(:survey_log_entries)).survey_log_entries

    assert do_you_smoke.survey_id == survey.id
    assert do_you_smoke.action_data == "Do you smoke?"
    assert do_you_smoke.action_type == "prompt"
    assert do_you_smoke.disposition == "queued"

    assert disposition_changed_to_contacted.survey_id == survey.id
    assert disposition_changed_to_contacted.action_data == "Contacted"
    assert disposition_changed_to_contacted.action_type == "disposition changed"
    assert disposition_changed_to_contacted.disposition == "queued"

    assert do_smoke.survey_id == survey.id
    assert do_smoke.action_data == "Yes"
    assert do_smoke.action_type == "response"
    assert do_smoke.disposition == "contacted"

    assert disposition_changed_to_started.survey_id == survey.id
    assert disposition_changed_to_started.action_data == "Started"
    assert disposition_changed_to_started.action_type == "disposition changed"
    assert disposition_changed_to_started.disposition == "contacted"

    assert do_you_exercise.survey_id == survey.id
    assert do_you_exercise.action_data == "Do you exercise"
    assert do_you_exercise.action_type == "prompt"
    assert do_you_exercise.disposition == "started"

    assert do_exercise.survey_id == survey.id
    assert do_exercise.action_data == "Yes"
    assert do_exercise.action_type == "response"
    assert do_exercise.disposition == "started"

    assert second_perfect_number.survey_id == survey.id
    assert second_perfect_number.action_data == "Which is the second perfect number?"
    assert second_perfect_number.action_type == "prompt"
    assert second_perfect_number.disposition == "started"

    assert ninety_nine.survey_id == survey.id
    assert ninety_nine.action_data == "99"
    assert ninety_nine.action_type == "response"
    assert ninety_nine.disposition == "started"

    assert question_number.survey_id == survey.id
    assert question_number.action_data == "What's the number of this question?"
    assert question_number.action_type == "prompt"
    assert question_number.disposition == "started"

    assert eleven.survey_id == survey.id
    assert eleven.action_data == "11"
    assert eleven.action_type == "response"
    assert eleven.disposition == "started"

    assert bye.survey_id == survey.id
    assert bye.action_data == "Bye"
    assert bye.action_type == "prompt"
    assert bye.disposition == "started"

    assert disposition_changed_to_completed.survey_id == survey.id
    assert disposition_changed_to_completed.action_data == "Completed"
    assert disposition_changed_to_completed.action_type == "disposition changed"
    assert disposition_changed_to_completed.disposition == "started"

    :ok = broker |> GenServer.stop
  end

  test "respondent flow via ivr with an empty thank you message" do
    [survey, _group, _test_channel, respondent, _phone_number] = create_running_survey_with_channel_and_respondent(@dummy_steps, "ivr")

    hd((survey |> Ask.Repo.preload(:questionnaires)).questionnaires)
    |> Questionnaire.changeset(%{
      settings: %{
        "error_message" => %{
          "en" => %{
            "sms" => "You have entered an invalid answer",
            "ivr" => %{
              "audio_source" => "tts",
              "text" => "You have entered an invalid answer (ivr)"
            }
          }
        },
        "thank_you_message" => %{
          "en" => %{
            "ivr" => %{
              "audio_source" => "tts",
              "text" => ""
            },
            "sms" => ""
          }
        }
      }
    })
    |> Repo.update!

    {:ok, logger} = SurveyLogger.start_link
    {:ok, broker} = Broker.start_link
    Broker.poll

    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"

    reply = Broker.sync_step(respondent, Flow.Message.answer())
    assert {:reply, ReplyHelper.ivr("Do you smoke?", "Do you smoke? Press 8 for YES, 9 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("9"))
    assert {:reply, ReplyHelper.ivr("Do you exercise", "Do you exercise? Press 1 for YES, 2 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("1"))
    assert {:reply, ReplyHelper.ivr("Which is the second perfect number?", "Which is the second perfect number")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("99"))
    assert {:reply, ReplyHelper.ivr("What's the number of this question?", "What's the number of this question")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("11"))
    assert :end = reply

    now = Timex.now
    interval = Interval.new(from: Timex.shift(now, seconds: -5), until: Timex.shift(now, seconds: 5), step: [seconds: 1])

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "completed"
    assert respondent.session == nil
    assert respondent.completed_at in interval

    :ok = logger |> GenServer.stop

    assert [enqueueing, answer, disposition_changed_to_contacted, do_you_smoke, do_smoke, disposition_changed_to_started, do_you_exercise, do_exercise, second_perfect_number, ninety_nine, question_number, eleven, disposition_changed_to_completed] = (respondent |> Repo.preload(:survey_log_entries)).survey_log_entries

    assert enqueueing.survey_id == survey.id
    assert enqueueing.action_data == "Enqueueing call"
    assert enqueueing.action_type == "contact"
    assert enqueueing.disposition == "queued"

    assert answer.survey_id == survey.id
    assert answer.action_data == "Answer"
    assert answer.action_type == "contact"
    assert answer.disposition == "queued"

    assert disposition_changed_to_contacted.survey_id == survey.id
    assert disposition_changed_to_contacted.action_data == "Contacted"
    assert disposition_changed_to_contacted.action_type == "disposition changed"
    assert disposition_changed_to_contacted.disposition == "queued"

    assert do_you_smoke.survey_id == survey.id
    assert do_you_smoke.action_data == "Do you smoke?"
    assert do_you_smoke.action_type == "prompt"
    assert do_you_smoke.disposition == "contacted"

    assert do_smoke.survey_id == survey.id
    assert do_smoke.action_data == "9"
    assert do_smoke.action_type == "response"
    assert do_smoke.disposition == "contacted"

    assert disposition_changed_to_started.survey_id == survey.id
    assert disposition_changed_to_started.action_data == "Started"
    assert disposition_changed_to_started.action_type == "disposition changed"
    assert disposition_changed_to_started.disposition == "contacted"

    assert do_you_exercise.survey_id == survey.id
    assert do_you_exercise.action_data == "Do you exercise"
    assert do_you_exercise.action_type == "prompt"
    assert do_you_exercise.disposition == "started"

    assert do_exercise.survey_id == survey.id
    assert do_exercise.action_data == "1"
    assert do_exercise.action_type == "response"
    assert do_exercise.disposition == "started"

    assert second_perfect_number.survey_id == survey.id
    assert second_perfect_number.action_data == "Which is the second perfect number?"
    assert second_perfect_number.action_type == "prompt"
    assert second_perfect_number.disposition == "started"

    assert ninety_nine.survey_id == survey.id
    assert ninety_nine.action_data == "99"
    assert ninety_nine.action_type == "response"
    assert ninety_nine.disposition == "started"

    assert question_number.survey_id == survey.id
    assert question_number.action_data == "What's the number of this question?"
    assert question_number.action_type == "prompt"
    assert question_number.disposition == "started"

    assert eleven.survey_id == survey.id
    assert eleven.action_data == "11"
    assert eleven.action_type == "response"
    assert eleven.disposition == "started"

    assert disposition_changed_to_completed.survey_id == survey.id
    assert disposition_changed_to_completed.action_data == "Completed"
    assert disposition_changed_to_completed.action_type == "disposition changed"
    assert disposition_changed_to_completed.disposition == "started"

    :ok = broker |> GenServer.stop
  end

  test "respondent flow via mobileweb with splitted message" do
    [survey, _group, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent(@mobileweb_dummy_steps, "mobileweb")

    quiz = hd(survey.questionnaires)
    quiz |> Questionnaire.changeset(%{settings: %{"mobile_web_sms_message" => "One#{Questionnaire.sms_split_separator}Two"}}) |> Repo.update!

    {:ok, _} = Broker.start_link
    Broker.poll

    assert_receive [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _, %Ask.Runtime.Reply{steps: [step]}]
    assert step == Ask.Runtime.ReplyStep.new(["One", "Two #{Routes.mobile_survey_url(Ask.Endpoint, :index, respondent.id, token: Respondent.token(respondent.id))}"], "Contact")
  end

  test "respondent flow with error msg and quota completed msg via sms" do
    [survey, _group, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent()

    quotas = %{
      "vars" => ["Smokes"],
      "buckets" => [
        %{
          "condition" => [%{"store" => "Smokes", "value" => "No"}],
          "quota" => 1,
          "count" => 1
        },
        %{
          "condition" => [%{"store" => "Smokes", "value" => "Yes"}],
          "quota" => 1,
          "count" => 0
        },
      ]
    }

    survey
    |> Repo.preload([:quota_buckets])
    |> Survey.changeset(%{quotas: quotas})
    |> Repo.update!


    quiz = hd((survey |> Ask.Repo.preload(:questionnaires)).questionnaires)
    quiz
    |> Questionnaire.changeset(%{
      quota_completed_steps: [
      %{
        "id" => "quota-completed-prompt",
        "type" => "multiple-choice",
        "title" => "Satisfaction",
        "prompt" => %{
          "en" => %{
            "sms" => "Did you enjoy this survey?"
          }
        },
        "store" => "satisfaction",
        "choices" => [
          %{
            "value" => "Yes",
            "responses" => %{
              "sms" => %{
                "en" => ["Yes", "Y", "1"]
              }
            },
            "skip_logic" => nil
          },
          %{
            "value" => "No",
            "responses" => %{
              "sms" => %{
                "en" => ["No", "N", "2"]
              }
            },
            "skip_logic" => nil
          }
        ],
      },
      %{
        "id" => "quota-completed-step",
        "type" => "explanation",
        "title" => "Completed",
        "prompt" => %{
          "en" => %{
            "sms" => "Quota completed",
            "ivr" => %{
              "audio_source" => "tts",
              "text" => "Quota completed (ivr)"
            }
          }
        },
        "skip_logic" => nil
      }],
      settings: %{
        "error_message" => %{"en" => %{"sms" => "Wrong answer"}}
      }
    })
    |> Repo.update!

    {:ok, logger} = SurveyLogger.start_link
    {:ok, broker} = Broker.start_link
    Broker.poll

    assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    respondent = Repo.get(Respondent, respondent.id)
    Broker.delivery_confirm(respondent, "Do you smoke?")

    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"
    reply = Broker.sync_step(respondent, Flow.Message.reply("Foo"))
    assert {:reply, ReplyHelper.error("Wrong answer", "Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    Broker.delivery_confirm(respondent, "Error")
    Broker.delivery_confirm(respondent, "Do you smoke?")

    reply = Broker.sync_step(respondent, Flow.Message.reply("No"))
    assert {:reply, ReplyHelper.simple("Satisfaction", "Did you enjoy this survey?")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    Broker.delivery_confirm(respondent, "Satisfaction")

    reply = Broker.sync_step(respondent, Flow.Message.reply("No"))
    assert {:end, {:reply, ReplyHelper.simple("Completed", "Quota completed")}} = reply

    respondent = Repo.get(Respondent, respondent.id)
    Broker.delivery_confirm(respondent, "Completed")

    :ok = logger |> GenServer.stop

    assert [do_you_smoke, disposition_changed_to_contacted, foo, disposition_changed_to_started, wrong_answer, do_you_smoke_again, dont_smoke, disposition_changed_to_rejected, satisfaction, dissatisfied, completed] = (respondent |> Repo.preload(:survey_log_entries)).survey_log_entries

    assert do_you_smoke.survey_id == survey.id
    assert do_you_smoke.action_data == "Do you smoke?"
    assert do_you_smoke.action_type == "prompt"
    assert do_you_smoke.disposition == "queued"

    assert disposition_changed_to_contacted.survey_id == survey.id
    assert disposition_changed_to_contacted.action_data == "Contacted"
    assert disposition_changed_to_contacted.action_type == "disposition changed"
    assert disposition_changed_to_contacted.disposition == "queued"

    assert foo.survey_id == survey.id
    assert foo.action_data == "Foo"
    assert foo.action_type == "response"
    assert foo.disposition == "contacted"

    assert disposition_changed_to_started.survey_id == survey.id
    assert disposition_changed_to_started.action_data == "Started"
    assert disposition_changed_to_started.action_type == "disposition changed"
    assert disposition_changed_to_started.disposition == "contacted"

    assert wrong_answer.survey_id == survey.id
    assert wrong_answer.action_data == "Error"
    assert wrong_answer.action_type == "prompt"
    assert wrong_answer.disposition == "started"

    assert do_you_smoke_again.survey_id == survey.id
    assert do_you_smoke_again.action_data == "Do you smoke?"
    assert do_you_smoke_again.action_type == "prompt"
    assert do_you_smoke_again.disposition == "started"

    assert dont_smoke.survey_id == survey.id
    assert dont_smoke.action_data == "No"
    assert dont_smoke.action_type == "response"
    assert dont_smoke.disposition == "started"

    assert disposition_changed_to_rejected.survey_id == survey.id
    assert disposition_changed_to_rejected.action_data == "Rejected"
    assert disposition_changed_to_rejected.action_type == "disposition changed"
    assert disposition_changed_to_rejected.disposition == "started"

    assert satisfaction.survey_id == survey.id
    assert satisfaction.action_data == "Satisfaction"
    assert satisfaction.action_type == "prompt"
    assert satisfaction.disposition == "rejected"

    assert dissatisfied.survey_id == survey.id
    assert dissatisfied.action_data == "No"
    assert dissatisfied.action_type == "response"
    assert dissatisfied.disposition == "rejected"

    assert completed.survey_id == survey.id
    assert completed.action_data == "Completed"
    assert completed.action_type == "prompt"
    assert completed.disposition == "rejected"

    :ok = broker |> GenServer.stop
  end

  test "respondent flow with error msg and quota completed msg via ivr" do
    [survey, _group, _test_channel, respondent, _phone_number] = create_running_survey_with_channel_and_respondent(@dummy_steps, "ivr")

    quotas = %{
      "vars" => ["Smokes"],
      "buckets" => [
        %{
          "condition" => [%{"store" => "Smokes", "value" => "No"}],
          "quota" => 1,
          "count" => 1
        },
        %{
          "condition" => [%{"store" => "Smokes", "value" => "Yes"}],
          "quota" => 1,
          "count" => 0
        },
      ]
    }

    survey
    |> Repo.preload([:quota_buckets])
    |> Survey.changeset(%{quotas: quotas})
    |> Repo.update!


    quiz = hd((survey |> Ask.Repo.preload(:questionnaires)).questionnaires)
    quiz
    |> Questionnaire.changeset(%{
      quota_completed_steps: [%{
        "id" => "quota-completed-step",
        "type" => "explanation",
        "title" => "Completed",
        "prompt" => %{
          "en" => %{
            "sms" => "Quota completed",
            "ivr" => %{
              "audio_source" => "tts",
              "text" => "Quota completed (ivr)"
            }
          }
        },
        "skip_logic" => nil
      }],
      settings: %{
        "error_message" => %{"en" => %{"ivr" => %{"text" => "Wrong answer", "audio_source" => "tts"}}}
      }
    })
    |> Repo.update!

    {:ok, logger} = SurveyLogger.start_link
    {:ok, broker} = Broker.start_link
    Broker.poll

    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"

    reply = Broker.sync_step(respondent, Flow.Message.answer())
    assert {:reply, ReplyHelper.ivr("Do you smoke?", "Do you smoke? Press 8 for YES, 9 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("3"))
    assert {:reply, ReplyHelper.error_ivr("Wrong answer", "Do you smoke?", "Do you smoke? Press 8 for YES, 9 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("9"))
    assert {:end, {:reply, ReplyHelper.ivr("Completed", "Quota completed (ivr)")}} = reply

    :ok = logger |> GenServer.stop

    assert [enqueueing, answer, disposition_changed_to_contacted, do_you_smoke, foo, disposition_changed_to_started, wrong_answer, do_you_smoke_again, dont_smoke, disposition_changed_to_rejected, completed] = (respondent |> Repo.preload(:survey_log_entries)).survey_log_entries

    assert enqueueing.survey_id == survey.id
    assert enqueueing.action_data == "Enqueueing call"
    assert enqueueing.action_type == "contact"
    assert enqueueing.disposition == "queued"

    assert answer.survey_id == survey.id
    assert answer.action_data == "Answer"
    assert answer.action_type == "contact"
    assert answer.disposition == "queued"

    assert disposition_changed_to_contacted.survey_id == survey.id
    assert disposition_changed_to_contacted.action_data == "Contacted"
    assert disposition_changed_to_contacted.action_type == "disposition changed"
    assert disposition_changed_to_contacted.disposition == "queued"

    assert do_you_smoke.survey_id == survey.id
    assert do_you_smoke.action_data == "Do you smoke?"
    assert do_you_smoke.action_type == "prompt"
    assert do_you_smoke.disposition == "contacted"

    assert foo.survey_id == survey.id
    assert foo.action_data == "3"
    assert foo.action_type == "response"
    assert foo.disposition == "contacted"

    assert disposition_changed_to_started.survey_id == survey.id
    assert disposition_changed_to_started.action_data == "Started"
    assert disposition_changed_to_started.action_type == "disposition changed"
    assert disposition_changed_to_started.disposition == "contacted"

    assert wrong_answer.survey_id == survey.id
    assert wrong_answer.action_data == "Error"
    assert wrong_answer.action_type == "prompt"
    assert wrong_answer.disposition == "started"

    assert do_you_smoke_again.survey_id == survey.id
    assert do_you_smoke_again.action_data == "Do you smoke?"
    assert do_you_smoke_again.action_type == "prompt"
    assert do_you_smoke_again.disposition == "started"

    assert dont_smoke.survey_id == survey.id
    assert dont_smoke.action_data == "9"
    assert dont_smoke.action_type == "response"
    assert dont_smoke.disposition == "started"

    assert disposition_changed_to_rejected.survey_id == survey.id
    assert disposition_changed_to_rejected.action_data == "Rejected"
    assert disposition_changed_to_rejected.action_type == "disposition changed"
    assert disposition_changed_to_rejected.disposition == "started"

    assert completed.survey_id == survey.id
    assert completed.action_data == "Completed"
    assert completed.action_type == "prompt"
    assert completed.disposition == "rejected"

    :ok = broker |> GenServer.stop
  end

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

    survey1 = Repo.get(Survey, survey1.id)
    survey2 = Repo.get(Survey, survey2.id)
    assert Survey.completed?(survey1)
    assert survey2.state == "running"
  end

  test "only polls surveys if today is not blocked" do
    survey1 = insert(:survey, %{schedule: Schedule.always(), state: "running"})
    survey2 = insert(:survey, %{schedule: Map.merge(Schedule.always(), %{blocked_days: [Date.utc_today()]}), state: "running"})

    Broker.handle_info(:poll, nil)

    survey1 = Repo.get(Survey, survey1.id)
    survey2 = Repo.get(Survey, survey2.id)
    assert Survey.completed?(survey1)
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

    survey = Repo.get(Survey, survey.id)
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

    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"
  end

  test "doesn't poll surveys with an end time schedule smaller than the current hour considering timezone" do
    survey = insert(:survey, %{schedule: Map.merge(Schedule.always(), %{start_time: ~T[10:00:00], end_time: ~T[12:00:00], timezone: "Asia/Shanghai"}), state: "running"})

    Broker.handle_info(:poll, nil, Timex.parse!("2016-01-01T11:00:00Z", "{ISO:Extended}"))

    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"
  end

  test "does poll surveys with an end time schedule higher than the current hour considering timezone" do
    survey = insert(:survey, %{schedule: Map.merge(Schedule.always(), %{start_time: ~T[10:00:00], end_time: ~T[12:00:00], timezone: "America/Buenos_Aires"}), state: "running"})

    Broker.handle_info(:poll, nil, Timex.parse!("2016-01-01T14:00:00Z", "{ISO:Extended}"))

    survey = Repo.get(Survey, survey.id)
    assert Survey.completed?(survey)
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
    survey = Repo.get(Survey, survey.id)
    assert Survey.completed?(survey)
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
    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"
  end

  test "increments quota bucket when a respondent completes the survey" do
    [survey, _group, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent()
    Survey.changeset(survey, %{quota_vars: ["Exercises", "Smokes"]}) |> Repo.update()

    selected_bucket = insert(:quota_bucket, survey: survey, condition: %{Smokes: "No", Exercises: "Yes"}, quota: 10, count: 0)
    insert(:quota_bucket, survey: survey, condition: %{Smokes: "No", Exercises: "No"}, quota: 10, count: 0)
    insert(:quota_bucket, survey: survey, condition: %{Smokes: "Yes", Exercises: "Yes"}, quota: 10, count: 0)
    insert(:quota_bucket, survey: survey, condition: %{Smokes: "Yes", Exercises: "No"}, quota: 10, count: 0)

    {:ok, broker} = Broker.start_link
    Broker.poll

    assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    respondent = Repo.get(Respondent, respondent.id)

    reply = Broker.sync_step(respondent, Flow.Message.reply("No"))
    assert {:reply, ReplyHelper.simple("Do you exercise", "Do you exercise? Reply 1 for YES, 2 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("Yes"))
    assert {:reply, ReplyHelper.simple("Which is the second perfect number?", "Which is the second perfect number??")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("99"))
    assert {:reply, ReplyHelper.simple("What's the number of this question?", "What's the number of this question??")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("11"))
    assert {:end, {:reply, ReplyHelper.simple("Thank you", "Thanks for completing this survey")}} = reply

    selected_bucket = QuotaBucket |> Repo.get(selected_bucket.id)
    assert selected_bucket.count == 1
    assert QuotaBucket
           |> Repo.all
           |> Enum.filter( fn (b) -> b.id != selected_bucket.id end)
           |> Enum.all?( fn (b) -> b.count == 0 end)
    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.disposition == "completed"

    :ok = broker |> GenServer.stop
  end

  test "increments quota bucket when a respondent completes the survey, with numeric condition" do
    [survey, _group, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent()
    Survey.changeset(survey, %{quota_vars: ["Exercises", "Smokes"]}) |> Repo.update()

    insert(:quota_bucket, survey: survey, condition: %{:Smokes => "No", :"Perfect Number" => [20, 30]}, quota: 10, count: 0)
    selected_bucket = insert(:quota_bucket, survey: survey, condition: %{:Smokes => "No", :"Perfect Number" => [31, 40]}, quota: 10, count: 0)
    insert(:quota_bucket, survey: survey, condition: %{:Smokes => "Yes", :"Perfect Number" => [20, 30]}, quota: 10, count: 0)
    insert(:quota_bucket, survey: survey, condition: %{:Smokes => "Yes", :"Perfect Number" => [31, 40]}, quota: 10, count: 0)

    {:ok, broker} = Broker.start_link
    Broker.poll

    assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    respondent = Repo.get(Respondent, respondent.id)

    reply = Broker.sync_step(respondent, Flow.Message.reply("No"))
    assert {:reply, ReplyHelper.simple("Do you exercise", "Do you exercise? Reply 1 for YES, 2 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("Yes"))
    assert {:reply, ReplyHelper.simple("Which is the second perfect number?", "Which is the second perfect number??")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("33"))
    assert {:reply, ReplyHelper.simple("What's the number of this question?", "What's the number of this question??")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("11"))
    assert {:end, {:reply, ReplyHelper.simple("Thank you", "Thanks for completing this survey")}} = reply

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.disposition == "completed"
    selected_bucket = QuotaBucket |> Repo.get(selected_bucket.id)
    assert selected_bucket.count == 1
    assert QuotaBucket
           |> Repo.all
           |> Enum.filter( fn (b) -> b.id != selected_bucket.id end)
           |> Enum.all?( fn (b) -> b.count == 0 end)

    :ok = broker |> GenServer.stop
  end

  test "marks the respondent as rejected when the bucket is completed" do
    [survey, _group, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent()
    Survey.changeset(survey, %{quota_vars: ["Exercises"]}) |> Repo.update()

    selected_bucket = insert(:quota_bucket, survey: survey, condition: %{:Exercises => "Yes"}, quota: 1, count: 1)
    insert(:quota_bucket, survey: survey, condition: %{:Exercises => "No"}, quota: 10, count: 0)

    {:ok, broker} = Broker.start_link
    Broker.poll

    assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    respondent = Repo.get(Respondent, respondent.id)

    reply = Broker.sync_step(respondent, Flow.Message.reply("No"))
    assert {:reply, ReplyHelper.simple("Do you exercise", "Do you exercise? Reply 1 for YES, 2 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("Yes"))
    assert :end = reply
    updated_respondent = Repo.get(Respondent, respondent.id)
    assert updated_respondent.state == "rejected"
    assert updated_respondent.disposition == "rejected"

    selected_bucket = QuotaBucket |> Repo.get(selected_bucket.id)
    assert selected_bucket.count == 1

    :ok = broker |> GenServer.stop
  end

  test "increments quota bucket when a respondent is flagged as completed" do
    [survey, _group, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent(@dummy_steps_with_flag)
    Survey.changeset(survey, %{quota_vars: ["Exercises", "Smokes"]}) |> Repo.update()

    selected_bucket = insert(:quota_bucket, survey: survey, condition: %{Smokes: "No", Exercises: "Yes"}, quota: 10, count: 0)
    insert(:quota_bucket, survey: survey, condition: %{Smokes: "No", Exercises: "No"}, quota: 10, count: 0)
    insert(:quota_bucket, survey: survey, condition: %{Smokes: "Yes", Exercises: "Yes"}, quota: 10, count: 0)
    insert(:quota_bucket, survey: survey, condition: %{Smokes: "Yes", Exercises: "No"}, quota: 10, count: 0)

    {:ok, broker} = Broker.start_link
    Broker.poll

    assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    respondent = Repo.get(Respondent, respondent.id)

    reply = Broker.sync_step(respondent, Flow.Message.reply("No"))
    assert {:reply, ReplyHelper.simple("Do you exercise", "Do you exercise? Reply 1 for YES, 2 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.disposition == "interim partial"

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("Yes"))
    assert {:reply, ReplyHelper.simple("Which is the second perfect number?", "Which is the second perfect number??")} = reply

    selected_bucket = QuotaBucket |> Repo.get(selected_bucket.id)
    assert selected_bucket.count == 1
    assert QuotaBucket
           |> Repo.all
           |> Enum.filter( fn (b) -> b.id != selected_bucket.id end)
           |> Enum.all?( fn (b) -> b.count == 0 end)
    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.disposition == "completed"

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("99"))
    assert {:reply, ReplyHelper.simple("What's the number of this question?", "What's the number of this question??")} = reply

    selected_bucket = QuotaBucket |> Repo.get(selected_bucket.id)
    assert selected_bucket.count == 1
    assert QuotaBucket
           |> Repo.all
           |> Enum.filter( fn (b) -> b.id != selected_bucket.id end)
           |> Enum.all?( fn (b) -> b.count == 0 end)
    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.disposition == "completed"

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("11"))
    assert {:end, {:reply, ReplyHelper.simple("Thank you", "Thanks for completing this survey")}} = reply

    selected_bucket = QuotaBucket |> Repo.get(selected_bucket.id)
    assert selected_bucket.count == 1
    assert QuotaBucket
           |> Repo.all
           |> Enum.filter( fn (b) -> b.id != selected_bucket.id end)
           |> Enum.all?( fn (b) -> b.count == 0 end)
    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.disposition == "completed"

    :ok = broker |> GenServer.stop
  end

  test "increments quota bucket when a respondent is flagged as completed, with a numeric condition defining the bucket after the flag was already specified" do
    [survey, _group, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent(@dummy_steps_with_flag)
    Survey.changeset(survey, %{quota_vars: ["Exercises", "Smokes"]}) |> Repo.update()

    insert(:quota_bucket, survey: survey, condition: %{:Smokes => "No", :"Perfect Number" => [20, 30]}, quota: 10, count: 0)
    selected_bucket = insert(:quota_bucket, survey: survey, condition: %{:Smokes => "No", :"Perfect Number" => [31, 40]}, quota: 10, count: 0)
    insert(:quota_bucket, survey: survey, condition: %{:Smokes => "Yes", :"Perfect Number" => [20, 30]}, quota: 10, count: 0)
    insert(:quota_bucket, survey: survey, condition: %{:Smokes => "Yes", :"Perfect Number" => [31, 40]}, quota: 10, count: 0)

    {:ok, broker} = Broker.start_link
    Broker.poll

    assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    respondent = Repo.get(Respondent, respondent.id)

    reply = Broker.sync_step(respondent, Flow.Message.reply("No"))
    assert {:reply, ReplyHelper.simple("Do you exercise", "Do you exercise? Reply 1 for YES, 2 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("Yes"))
    assert {:reply, ReplyHelper.simple("Which is the second perfect number?", "Which is the second perfect number??")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("33"))
    assert {:reply, ReplyHelper.simple("What's the number of this question?", "What's the number of this question??")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("11"))
    assert {:end, {:reply, ReplyHelper.simple("Thank you", "Thanks for completing this survey")}} = reply

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.disposition == "completed"
    selected_bucket = QuotaBucket |> Repo.get(selected_bucket.id)
    assert selected_bucket.count == 1
    assert QuotaBucket
           |> Repo.all
           |> Enum.filter( fn (b) -> b.id != selected_bucket.id end)
           |> Enum.all?( fn (b) -> b.count == 0 end)

    :ok = broker |> GenServer.stop
  end

  test "increments quota bucket when a respondent is flagged as partial" do
    test_channel = TestChannel.new
    channel = insert(:channel, settings: test_channel |> TestChannel.settings, type: "sms")
    quiz = insert(:questionnaire, steps: @dummy_steps_with_flag)
    survey = insert(:survey, %{schedule: Schedule.always(), state: "running", questionnaires: [quiz], mode: [["sms"]], count_partial_results: true})
    group = insert(:respondent_group, survey: survey, respondents_count: 1) |> Repo.preload(:channels)

    RespondentGroupChannel.changeset(%RespondentGroupChannel{}, %{respondent_group_id: group.id, channel_id: channel.id, mode: channel.type}) |> Repo.insert

    respondent = insert(:respondent, survey: survey, respondent_group: group)
    phone_number = respondent.sanitized_phone_number

    Survey.changeset(survey, %{quota_vars: ["Smokes"]}) |> Repo.update()

    selected_bucket = insert(:quota_bucket, survey: survey, condition: %{Smokes: "No"}, quota: 10, count: 0)
    insert(:quota_bucket, survey: survey, condition: %{Smokes: "Yes"}, quota: 10, count: 0)

    {:ok, broker} = Broker.start_link
    Broker.poll

    assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    respondent = Repo.get(Respondent, respondent.id)
    Broker.delivery_confirm(respondent, "Do you smoke?")

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("No"))
    assert {:reply, ReplyHelper.simple("Do you exercise", "Do you exercise? Reply 1 for YES, 2 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.disposition == "interim partial"

    selected_bucket = QuotaBucket |> Repo.get(selected_bucket.id)
    assert selected_bucket.count == 1
    assert QuotaBucket
           |> Repo.all
           |> Enum.filter( fn (b) -> b.id != selected_bucket.id end)
           |> Enum.all?( fn (b) -> b.count == 0 end)

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("Yes"))
    assert {:reply, ReplyHelper.simple("Which is the second perfect number?", "Which is the second perfect number??")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.disposition == "completed"

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("99"))
    assert {:reply, ReplyHelper.simple("What's the number of this question?", "What's the number of this question??")} = reply

    selected_bucket = QuotaBucket |> Repo.get(selected_bucket.id)
    assert selected_bucket.count == 1
    assert QuotaBucket
           |> Repo.all
           |> Enum.filter( fn (b) -> b.id != selected_bucket.id end)
           |> Enum.all?( fn (b) -> b.count == 0 end)
    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.disposition == "completed"

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("11"))
    assert {:end, {:reply, ReplyHelper.simple("Thank you", "Thanks for completing this survey")}} = reply

    selected_bucket = QuotaBucket |> Repo.get(selected_bucket.id)
    assert selected_bucket.count == 1
    assert QuotaBucket
           |> Repo.all
           |> Enum.filter( fn (b) -> b.id != selected_bucket.id end)
           |> Enum.all?( fn (b) -> b.count == 0 end)
    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.disposition == "completed"

    :ok = broker |> GenServer.stop
  end

  test "increments quota bucket when a respondent is flagged as partial before being in a bucket" do
    test_channel = TestChannel.new
    channel = insert(:channel, settings: test_channel |> TestChannel.settings, type: "sms")
    quiz = insert(:questionnaire, steps: @dummy_steps_with_flag)
    survey = insert(:survey, %{schedule: Schedule.always(), state: "running", questionnaires: [quiz], mode: [["sms"]], count_partial_results: true})
    group = insert(:respondent_group, survey: survey, respondents_count: 1) |> Repo.preload(:channels)

    RespondentGroupChannel.changeset(%RespondentGroupChannel{}, %{respondent_group_id: group.id, channel_id: channel.id, mode: channel.type}) |> Repo.insert

    respondent = insert(:respondent, survey: survey, respondent_group: group)
    phone_number = respondent.sanitized_phone_number

    Survey.changeset(survey, %{quota_vars: ["Exercises"]}) |> Repo.update()

    selected_bucket = insert(:quota_bucket, survey: survey, condition: %{Exercises: "Yes"}, quota: 10, count: 0)
    insert(:quota_bucket, survey: survey, condition: %{Exercises: "No"}, quota: 10, count: 0)

    {:ok, broker} = Broker.start_link
    Broker.poll

    assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("No"))
    respondent = Repo.get(Respondent, respondent.id)

    assert {:reply, ReplyHelper.simple("Do you exercise", "Do you exercise? Reply 1 for YES, 2 for NO")} = reply

    assert respondent.disposition == "interim partial"

    reply = Broker.sync_step(respondent, Flow.Message.reply("Yes"))

    assert {:reply, ReplyHelper.simple("Which is the second perfect number?", "Which is the second perfect number??")} = reply
    respondent = Repo.get(Respondent, respondent.id)
    selected_bucket = QuotaBucket |> Repo.get(selected_bucket.id)

    assert selected_bucket.count == 1
    assert QuotaBucket
           |> Repo.all
           |> Enum.filter( fn (b) -> b.id != selected_bucket.id end)
           |> Enum.all?( fn (b) -> b.count == 0 end)
    assert respondent.disposition == "completed"

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("99"))
    assert {:reply, ReplyHelper.simple("What's the number of this question?", "What's the number of this question??")} = reply

    selected_bucket = QuotaBucket |> Repo.get(selected_bucket.id)
    assert selected_bucket.count == 1
    assert QuotaBucket
           |> Repo.all
           |> Enum.filter( fn (b) -> b.id != selected_bucket.id end)
           |> Enum.all?( fn (b) -> b.count == 0 end)
    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.disposition == "completed"

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("11"))
    assert {:end, {:reply, ReplyHelper.simple("Thank you", "Thanks for completing this survey")}} = reply

    selected_bucket = QuotaBucket |> Repo.get(selected_bucket.id)
    assert selected_bucket.count == 1
    assert QuotaBucket
           |> Repo.all
           |> Enum.filter( fn (b) -> b.id != selected_bucket.id end)
           |> Enum.all?( fn (b) -> b.count == 0 end)
    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.disposition == "completed"

    :ok = broker |> GenServer.stop
  end

  test "doesn't stop survey when there's an uncaught exception" do
    # First, we create a quiz with a single step with an invalid skip_logic value for the "Yes" choice
    step = Ask.StepBuilder
      .multiple_choice_step(
        id: "bbb",
        title: "Do you exercise",
        prompt: Ask.StepBuilder.prompt(
          sms: Ask.StepBuilder.sms_prompt("Do you exercise? Reply 1 for YES, 2 for NO")
        ),
        store: "Exercises",
        choices: [
          Ask.StepBuilder.choice(value: "Yes", responses: Ask.StepBuilder.responses(sms: ["Yes", "Y", "1"], ivr: ["1"]), skip_logic: ""),
          Ask.StepBuilder.choice(value: "No", responses: Ask.StepBuilder.responses(sms: ["No", "N", "2"], ivr: ["2"]))
        ]
      )

    [survey, _group, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent([step])

    {:ok, broker} = Broker.start_link
    Broker.poll

    assert_received [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _token, ReplyHelper.simple("Do you exercise", "Do you exercise? Reply 1 for YES, 2 for NO")]

    respondent = Repo.get(Respondent, respondent.id)

    # Respondent says 1 (i.e.: Yes), causing an invalid skip_logic to be inspected
    Broker.sync_step(respondent, Flow.Message.reply("1"))

    # If there's a problem with one respondent, continue the survey with others
    # and mark this one as failed
    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "failed"

    :ok = broker |> GenServer.stop
  end

  test "reloads respondent if stale" do
    [survey, _, _, respondent, _] = create_running_survey_with_channel_and_respondent()
    survey |> Survey.changeset(%{sms_retry_configuration: "2m"}) |> Repo.update!

    {:ok, _} = Broker.start_link
    Broker.handle_info(:poll, nil)

    respondent = Repo.get(Respondent, respondent.id)
    session = respondent.session |> Ask.Runtime.Session.load
    Broker.retry_respondent(respondent)

    Broker.sync_step_internal(session, Flow.Message.reply("Yes"))

    updated_respondent = Repo.get(Respondent, respondent.id)
    assert updated_respondent.state == "active"

    now = Timex.now
    interval = Interval.new(from: Timex.shift(now, minutes: 9), until: Timex.shift(now, minutes: 11), step: [seconds: 1])
    assert updated_respondent.timeout_at in interval
  end

  test "marks as failed after 3 successive wrong replies if there are no more retries" do
    [survey, _, _, respondent, _] = create_running_survey_with_channel_and_respondent(@dummy_steps, "ivr")

    {:ok, broker} = Broker.start_link
    Broker.poll

    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"

    reply = Broker.sync_step(respondent, Flow.Message.answer())
    assert {:reply, ReplyHelper.ivr("Do you smoke?", "Do you smoke? Press 8 for YES, 9 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("3"))
    assert {:reply, ReplyHelper.error_ivr("You have entered an invalid answer (ivr)", "Do you smoke?", "Do you smoke? Press 8 for YES, 9 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("3"))
    assert {:reply, ReplyHelper.error_ivr("You have entered an invalid answer (ivr)", "Do you smoke?", "Do you smoke? Press 8 for YES, 9 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("3"))
    assert :end = reply

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "failed"
    assert respondent.disposition == "breakoff"

    :ok = broker |> GenServer.stop
  end

  test "does not mark as failed after 3 successive wrong replies when there are retries left" do
    [survey, _, _, respondent, _] = create_running_survey_with_channel_and_respondent(@dummy_steps, "ivr")
    survey |> Survey.changeset(%{ivr_retry_configuration: "10m"}) |> Repo.update!

    {:ok, broker} = Broker.start_link
    Broker.poll

    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"

    reply = Broker.sync_step(respondent, Flow.Message.answer())
    assert {:reply, ReplyHelper.ivr("Do you smoke?", "Do you smoke? Press 8 for YES, 9 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("3"))
    assert {:reply, ReplyHelper.error_ivr("You have entered an invalid answer (ivr)", "Do you smoke?", "Do you smoke? Press 8 for YES, 9 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("3"))
    assert {:reply, ReplyHelper.error_ivr("You have entered an invalid answer (ivr)", "Do you smoke?", "Do you smoke? Press 8 for YES, 9 for NO")} = reply

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("3"))
    assert :end = reply

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"
    assert respondent.disposition == "started"

    :ok = broker |> GenServer.stop
  end

  test "reply via another channel (sms when ivr is the current one)" do
    sms_test_channel = TestChannel.new(false, true)
    sms_channel = insert(:channel, settings: sms_test_channel |> TestChannel.settings, type: "sms")

    ivr_test_channel = TestChannel.new(false, false)
    ivr_channel = insert(:channel, settings: ivr_test_channel |> TestChannel.settings, type: "ivr")

    quiz = insert(:questionnaire, steps: @dummy_steps)
    survey = insert(:survey, %{schedule: Schedule.always(), state: "running", questionnaires: [quiz], mode: [["ivr", "sms"]]})
    group = insert(:respondent_group, survey: survey, respondents_count: 1) |> Repo.preload(:channels)

    RespondentGroupChannel.changeset(%RespondentGroupChannel{}, %{respondent_group_id: group.id, channel_id: sms_channel.id, mode: "sms"}) |> Repo.insert
    RespondentGroupChannel.changeset(%RespondentGroupChannel{}, %{respondent_group_id: group.id, channel_id: ivr_channel.id, mode: "ivr"}) |> Repo.insert

    respondent = insert(:respondent, survey: survey, respondent_group: group)

    {:ok, _} = Broker.start_link
    Broker.handle_info(:poll, nil)

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("Yes"), "sms")
    assert {:reply, ReplyHelper.simple("Do you exercise", "Do you exercise? Reply 1 for YES, 2 for NO")} = reply
  end

  test "reply via another channel (mobileweb when sms is the current one)" do
    sms_test_channel = TestChannel.new(false, true)
    sms_channel = insert(:channel, settings: sms_test_channel |> TestChannel.settings, type: "mobileweb")

    ivr_test_channel = TestChannel.new(false, false)
    ivr_channel = insert(:channel, settings: ivr_test_channel |> TestChannel.settings, type: "sms")

    quiz = insert(:questionnaire, steps: @mobileweb_dummy_steps)
    survey = insert(:survey, %{schedule: Schedule.always(), state: "running", questionnaires: [quiz], mode: [["sms", "mobileweb"]]})
    group = insert(:respondent_group, survey: survey, respondents_count: 1) |> Repo.preload(:channels)

    RespondentGroupChannel.changeset(%RespondentGroupChannel{}, %{respondent_group_id: group.id, channel_id: sms_channel.id, mode: "mobileweb"}) |> Repo.insert
    RespondentGroupChannel.changeset(%RespondentGroupChannel{}, %{respondent_group_id: group.id, channel_id: ivr_channel.id, mode: "sms"}) |> Repo.insert

    respondent = insert(:respondent, survey: survey, respondent_group: group)

    {:ok, _} = Broker.start_link
    Broker.handle_info(:poll, nil)

    respondent = Repo.get(Respondent, respondent.id)
    reply = Broker.sync_step(respondent, Flow.Message.reply("Yes"), "mobileweb")
    assert {:reply, ReplyHelper.simple("Do you exercise", "Do you exercise?")} = reply
  end

  test "ignore answers from sms when mode is not one of the survey modes" do
    [survey, _group, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent(@mobileweb_dummy_steps, "mobileweb")
    survey |> Survey.changeset(%{mobileweb_retry_configuration: "10m"}) |> Repo.update

    {:ok, broker} = Broker.start_link
    Broker.poll

    assert_receive [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _, ReplyHelper.simple("Contact", message)]
    assert message == "Please enter #{Routes.mobile_survey_url(Ask.Endpoint, :index, respondent.id, token: Respondent.token(respondent.id))}"

    survey = Repo.get(Survey, survey.id)
    assert survey.state == "running"

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.state == "active"

    respondent = Repo.get(Respondent, respondent.id)
    assert :end = Broker.sync_step(respondent, Flow.Message.reply("Yes"), "sms")

    :ok = broker |> GenServer.stop
  end

  test "accept delivery confirm when mode is mobile web" do
    [_survey, _group, test_channel, respondent, phone_number] = create_running_survey_with_channel_and_respondent(@mobileweb_dummy_steps, "mobileweb")
    {:ok, _broker} = Broker.start_link
    Broker.poll

    assert_receive [:ask, ^test_channel, %Respondent{sanitized_phone_number: ^phone_number}, _, ReplyHelper.simple("Contact", message)]
    assert message == "Please enter #{Routes.mobile_survey_url(Ask.Endpoint, :index, respondent.id, token: Respondent.token(respondent.id))}"

    respondent = Repo.get(Respondent, respondent.id)
    Broker.delivery_confirm(respondent, "Contact", "sms")

    respondent = Repo.get(Respondent, respondent.id)
    assert respondent.disposition == "contacted"
  end

  test "it doesn't crash on channel_failed when there's no session" do
    respondent = insert(:respondent)
    assert Broker.channel_failed(respondent) == :ok
  end

  test "when channel fails a survey log entry is created" do
    [survey, _group, _test_channel, respondent, _phone_number] = create_running_survey_with_channel_and_respondent(@dummy_steps, "ivr")

    {:ok, broker} = Broker.start_link
    {:ok, logger} = SurveyLogger.start_link
    Broker.poll

    respondent = Repo.get(Respondent, respondent.id)

    Broker.channel_failed(respondent, "The channel failed")

    disposition_histories = Repo.all(RespondentDispositionHistory)
    assert disposition_histories |> length == 2

    [queued_history, failed_history] = disposition_histories
    assert queued_history.disposition == "queued"
    assert failed_history.disposition == "failed"

    :ok = logger |> GenServer.stop

    [enqueueing, channel_failed, disposition_changed_to_failed] = (respondent |> Repo.preload(:survey_log_entries)).survey_log_entries

    assert enqueueing.survey_id == survey.id
    assert enqueueing.action_data == "Enqueueing call"
    assert enqueueing.action_type == "contact"
    assert enqueueing.disposition == "queued"

    assert channel_failed.survey_id == survey.id
    assert channel_failed.action_data == "The channel failed"
    assert channel_failed.action_type == "contact"
    assert channel_failed.disposition == "queued"

    assert disposition_changed_to_failed.survey_id == survey.id
    assert disposition_changed_to_failed.action_data == "Failed"
    assert disposition_changed_to_failed.action_type == "disposition changed"
    assert disposition_changed_to_failed.disposition == "queued"

    :ok = broker |> GenServer.stop
  end

  test "respondent phone number is masked in logs" do
    [survey, group, _, _, _] = create_running_survey_with_channel_and_respondent()

    phone_number = "1-734-555-1212"
    respondent = insert(:respondent, survey: survey, respondent_group: group, phone_number: phone_number, sanitized_phone_number: Ask.Respondent.sanitize_phone_number(phone_number))

    {:ok, logger} = SurveyLogger.start_link
    {:ok, broker} = Broker.start_link
    Broker.poll

    Broker.delivery_confirm(Repo.get(Respondent, respondent.id), "Do you smoke?")

    reply = Broker.sync_step(Repo.get(Respondent, respondent.id), Flow.Message.reply("1-734-555-1212"))
    assert {:reply, ReplyHelper.error("You have entered an invalid answer", "Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")} = reply
    reply = Broker.sync_step(Repo.get(Respondent, respondent.id), Flow.Message.reply("fooo (1-734) 555 1212 bar"))
    assert {:reply, ReplyHelper.error("You have entered an invalid answer", "Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")} = reply
    reply = Broker.sync_step(Repo.get(Respondent, respondent.id), Flow.Message.reply("fooo (1734) 555.1212 bar"))
    assert :end = reply

    :ok = logger |> GenServer.stop

    assert [do_you_smoke, disposition_changed_to_contacted, response1, disposition_changed_to_started, response2, response3, disposition_changed_to_breakoff] = (Repo.get(Respondent, respondent.id) |> Repo.preload(:survey_log_entries)).survey_log_entries

    assert do_you_smoke.survey_id == survey.id
    assert do_you_smoke.action_data == "Do you smoke?"
    assert do_you_smoke.action_type == "prompt"
    assert do_you_smoke.disposition == "queued"

    assert disposition_changed_to_contacted.survey_id == survey.id
    assert disposition_changed_to_contacted.action_data == "Contacted"
    assert disposition_changed_to_contacted.action_type == "disposition changed"
    assert disposition_changed_to_contacted.disposition == "queued"

    assert response1.survey_id == survey.id
    assert response1.action_data == "1-734-5##-####"
    assert response1.action_type == "response"
    assert response1.disposition == "contacted"

    assert disposition_changed_to_started.survey_id == survey.id
    assert disposition_changed_to_started.action_data == "Started"
    assert disposition_changed_to_started.action_type == "disposition changed"
    assert disposition_changed_to_started.disposition == "contacted"

    assert response2.survey_id == survey.id
    assert response2.action_data == "fooo (1-734) 5## #### bar"
    assert response2.action_type == "response"
    assert response2.disposition == "started"

    assert response3.survey_id == survey.id
    assert response3.action_data == "fooo (1734) 5##.#### bar"
    assert response3.action_type == "response"
    assert response3.disposition == "started"

    assert disposition_changed_to_breakoff.survey_id == survey.id
    assert disposition_changed_to_breakoff.action_data == "Breakoff"
    assert disposition_changed_to_breakoff.action_type == "disposition changed"
    assert disposition_changed_to_breakoff.disposition == "started"

    :ok = broker |> GenServer.stop
  end

  test "respondent phone number is masked if it's part of a response" do
    phone_number = "1-734-555-1212"
    respondent = insert(:respondent, phone_number: phone_number, sanitized_phone_number: Ask.Respondent.sanitize_phone_number(phone_number))

    [
      {"1-734-5##-####", "1-734-555-1212"},
      {"fooo (1-734) 5## #### bar", "fooo (1-734) 555 1212 bar"},
      {"fooo (1734) 5##.#### bar", "fooo (1734) 555.1212 bar"},
      {"fooo (1 734) 5##-#### bar", "fooo (1 734) 555-1212 bar"},
      {"fooo (1)(734) 5###### bar", "fooo (1)(734) 5551212 bar"},
      {"fooo (1)(734)5###### bar", "fooo (1)(734)5551212 bar"},
      {"fooo 1 734 5## #### bar", "fooo 1 734 555 1212 bar"},
      {"fooo 1.734.5##.#### bar", "fooo 1.734.555.1212 bar"},
      {"fooo 1-734-5##-#### bar", "fooo 1-734-555-1212 bar"},
      {"fooo 17345###### bar", "fooo 17345551212 bar"},
      {"fooo (734) 5## #### bar", "fooo (734) 555 1212 bar"},
      {"fooo (734) 5##.#### bar", "fooo (734) 555.1212 bar"},
      {"fooo (734) 5##-#### bar", "fooo (734) 555-1212 bar"},
      {"fooo (734) 5###### bar", "fooo (734) 5551212 bar"},
      {"fooo (734)5###### bar", "fooo (734)5551212 bar"},
      {"fooo 734 5## #### bar", "fooo 734 555 1212 bar"},
      {"fooo 734.5##.#### bar", "fooo 734.555.1212 bar"},
      {"fooo 734-5##-#### bar", "fooo 734-555-1212 bar"},
      {"fooo 7345###### bar", "fooo 7345551212 bar"},
      {"fooo 5## #### bar", "fooo 555 1212 bar"},
      {"fooo 5##.#### bar", "fooo 555.1212 bar"},
      {"fooo 5##-#### bar", "fooo 555-1212 bar"},
      {"fooo 5###### bar", "fooo 5551212 bar"},
      {"1-734-5##-#### 1-734-5##-####", "1-734-555-1212 1-734-555-1212"},
      {"fooo 5## #### bar 5## #### bar fooo 5## #### x", "fooo 555 1212 bar 555 1212 bar fooo 555 1212 x"},
      {"fooo 7.3|4:5;#-#*#-#/### bar", "fooo 7.3|4:5;5-5*1-2/1#2 bar"}
    ]
    |> Enum.each(fn {masked_response, response} ->
      assert Flow.Message.reply(masked_response)
        == Broker.mask_phone_number(respondent, Flow.Message.reply(response))
    end)
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

  def create_running_survey_with_channel_and_respondent(steps \\ @dummy_steps, mode \\ "sms") do
    test_channel = TestChannel.new(false, mode == "sms")

    channel_type = case mode do
      "mobileweb" -> "sms"
      _ -> mode
    end

    channel = insert(:channel, settings: test_channel |> TestChannel.settings, type: channel_type)
    quiz = insert(:questionnaire, steps: steps, quota_completed_steps: nil)
    survey = insert(:survey, %{schedule: Schedule.always(), state: "running", questionnaires: [quiz], mode: [[mode]]})
    group = insert(:respondent_group, survey: survey, respondents_count: 1) |> Repo.preload(:channels)

    RespondentGroupChannel.changeset(%RespondentGroupChannel{}, %{respondent_group_id: group.id, channel_id: channel.id, mode: mode}) |> Repo.insert

    respondent = insert(:respondent, survey: survey, respondent_group: group)
    phone_number = respondent.sanitized_phone_number

    [survey, group, test_channel, respondent, phone_number]
  end

  def create_several_respondents(survey, group, n) when n <= 1 do
    [insert(:respondent, survey: survey, respondent_group: group)]
  end

  def create_several_respondents(survey, group, n) do
    [create_several_respondents(survey, group, n - 1) | insert(:respondent, survey: survey, respondent_group: group)]
  end

  def assert_respondents_by_state(survey, active, pending) do
    [a, p] = get_respondents_by_state(survey)

    assert a == active
    assert p == pending
  end

  def get_respondents_by_state(survey) do
    by_state = Repo.all(
      from r in assoc(survey, :respondents),
      group_by: :state,
      select: {r.state, count("*")}) |> Enum.into(%{})
    [by_state["active"] || 0, by_state["pending"] || 0]
  end

  defp day_after_tomorrow_schedule_day_of_week() do
    {erl_date, _} = Timex.now |> Timex.to_erl
    case :calendar.day_of_the_week(erl_date) do
      1 -> %Ask.DayOfWeek{wed: true}
      2 -> %Ask.DayOfWeek{thu: true}
      3 -> %Ask.DayOfWeek{fri: true}
      4 -> %Ask.DayOfWeek{sat: true}
      5 -> %Ask.DayOfWeek{sun: true}
      6 -> %Ask.DayOfWeek{mon: true}
      7 -> %Ask.DayOfWeek{tue: true}
    end
  end

  defp mark_n_active_respondents_as(new_state, n) do
    Repo.all(from r in Respondent, where: r.state == "active", limit: ^n)
    |> Enum.map(fn respondent ->
      Repo.update(respondent |> change |> Respondent.changeset(%{state: new_state}))
    end)
  end
end
