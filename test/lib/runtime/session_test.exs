defmodule Ask.SessionTest do
  use Ask.ConnCase
  use Ask.DummySteps
  import Ask.Factory
  import Ask.StepBuilder
  alias Ask.Runtime.Session
  alias Ask.Runtime.SessionModeProvider
  alias Ask.TestChannel
  alias Ask.Runtime.{Flow, Reply, ReplyHelper, SurveyLogger}
  alias Ask.{Survey, SurveyLogEntry, Respondent, QuotaBucket, Questionnaire, Schedule, Stats}
  require Ask.Runtime.ReplyHelper

  setup do
    quiz = insert(:questionnaire, steps: @dummy_steps)
    |> Questionnaire.changeset(%{settings: %{"thank_you_message" => nil} })
    |> Repo.update!

    respondent = insert(:respondent)
    test_channel = TestChannel.new
    channel = insert(:channel, settings: test_channel |> TestChannel.settings)
    {:ok, quiz: quiz, respondent: respondent, test_channel: test_channel, channel: channel}
  end

  test "session load should default to Schedule.always when nil (for sessions created before the schedule was added there)", %{quiz: quiz, respondent: respondent, channel: channel} do
    {:ok, session, _, _} = Session.start(quiz, respondent, channel, "sms", Schedule.default)

    session = session
      |> Session.dump

    session = %{session | schedule: nil}
      |> Poison.encode!
      |> Poison.decode!
      |> Session.load

    assert session.schedule == Schedule.always
  end

  test "start", %{quiz: quiz, respondent: respondent, test_channel: test_channel, channel: channel} do
    {:ok, %{respondent: respondent} = session, _, timeout} = Session.start(quiz, respondent, channel, "sms", Schedule.always())
    assert %Session{token: token} = session
    assert 10 = timeout
    assert token != nil

    assert_receive [:setup, ^test_channel, ^respondent, ^token]
    assert_receive [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    assert 1 == respondent.stats |> Stats.attempts(:sms)
  end

  describe "sections" do
    @language_selection [language_selection_step(
        id: Ecto.UUID.generate,
        title: "Language Selection",
        prompt: %{
          "sms" => sms_prompt("Reply 1 for English, mande 2 para Español"),
          "ivr" => tts_prompt("Press 1 for English, aprete 2 para Español")
        },
        store: "language",
        choices: ["en", "es"]
      )]

    test "updates section_order on session start", %{respondent: respondent, channel: channel} do
      quiz = build(:questionnaire, steps: @language_selection ++ @three_sections_all_random)

      {:ok, _, _, _} = Session.start(quiz, respondent, channel, "sms", Schedule.always())

      %Respondent{section_order: section_order} = respondent |> Repo.reload
      assert section_order
      assert Enum.sort(section_order, &(&1 <= &2)) == [0,1,2,3]
    end
  end

  test "start with web mode", %{quiz: quiz, respondent: respondent, test_channel: test_channel, channel: channel} do
    {:ok, %{respondent: respondent} = session, _, timeout} = Session.start(quiz, respondent, channel, "mobileweb", Schedule.always())
    assert %Session{token: token} = session
    assert 10 = timeout
    assert token != nil

    assert_receive [:setup, ^test_channel, ^respondent, ^token]
    assert_receive [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Contact", message)]
    assert message == "Please enter #{Ask.Endpoint.url}/mobile_survey/#{respondent.id}?token=#{Respondent.token(respondent.id)}"

    assert 1 == respondent.stats |> Stats.attempts(:mobileweb)
  end

  test "applies first pattern that matches when starting", %{quiz: quiz} do
    patterns = [
      %{"input" => "22XXXX", "output" => "5XXXX"},
      %{"input" => "XXXX", "output" => "5XXXX"},
      %{"input" => "XXXX", "output" => "4XXXX"}
    ]
    test_channel = TestChannel.new
    channel = insert(:channel, settings: test_channel |> TestChannel.settings, patterns: patterns)
    respondent = insert(:respondent, phone_number: "12 34", sanitized_phone_number: "1234")

    {:ok, %{respondent: respondent}, _, _} = Session.start(quiz, respondent, channel, "sms", Schedule.always())

    assert respondent.sanitized_phone_number == "51234"
    assert (Respondent |> Repo.get(respondent.id)).sanitized_phone_number == "51234"
  end

  test "sanitized_phone_number remains the same when starting and channel has no patterns", %{quiz: quiz} do
    test_channel = TestChannel.new
    channel = insert(:channel, settings: test_channel |> TestChannel.settings, patterns: [])
    respondent = insert(:respondent, phone_number: "12 34", sanitized_phone_number: "1234")

    {:ok, %{respondent: respondent}, _, _} = Session.start(quiz, respondent, channel, "sms", Schedule.always())

    assert respondent.sanitized_phone_number == "1234"
    assert (Respondent |> Repo.get(respondent.id)).sanitized_phone_number == "1234"
  end

  test "sanitized_phone_number remains the same when starting and no pattern matches", %{quiz: quiz} do
    patterns = [
      %{"input" => "22XXXX", "output" => "5XXXX"},
      %{"input" => "1234XXXX5", "output" => "5XXXX"},
      %{"input" => "XXX", "output" => "1XXX"}
    ]
    test_channel = TestChannel.new
    channel = insert(:channel, settings: test_channel |> TestChannel.settings, patterns: patterns)
    respondent = insert(:respondent, phone_number: "12 34", sanitized_phone_number: "1234")

    {:ok, %{respondent: respondent}, _, _} = Session.start(quiz, respondent, channel, "sms", Schedule.always())

    assert respondent.sanitized_phone_number == "1234"
    assert (Respondent |> Repo.get(respondent.id)).sanitized_phone_number == "1234"
  end

  test "reloading the page should not consume retries in mobileweb mode", %{respondent: respondent, test_channel: test_channel, channel: channel} do
    quiz = insert(:questionnaire, steps: @mobileweb_dummy_steps)
    retries = [1, 2, 3]

    {:ok, %{respondent: respondent} = session, _, _} = Session.start(quiz, respondent, channel, "mobileweb", Schedule.always(), retries)
    assert 1 == respondent.stats |> Stats.attempts(:mobileweb)
    assert %Session{token: token} = session
    assert token != nil

    assert_receive [:setup, ^test_channel, ^respondent, ^token]
    assert_receive [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Contact", message)]
    assert message == "Please enter #{Ask.Endpoint.url}/mobile_survey/#{respondent.id}?token=#{Respondent.token(respondent.id)}"

    assert {:ok, %Session{current_mode: %{retries: ^retries}} = session, ReplyHelper.simple("Let there be rock", "Welcome to the survey!"), _} = Session.sync_step(session, Flow.Message.answer())
    assert {:ok, %Session{current_mode: %{retries: ^retries}} = session, ReplyHelper.simple("Let there be rock", "Welcome to the survey!"), _} = Session.sync_step(session, Flow.Message.answer())
    assert {:ok, %Session{current_mode: %{retries: ^retries}} = session, ReplyHelper.simple("Let there be rock", "Welcome to the survey!"), _} = Session.sync_step(session, Flow.Message.answer())

    step_result = Session.sync_step(session, Flow.Message.reply(""))
    assert {:ok, session, ReplyHelper.simple("Do you smoke?", "Do you smoke?"), _} = step_result

    assert {:ok, %Session{current_mode: %{retries: ^retries}} = session, ReplyHelper.simple("Do you smoke?", "Do you smoke?"), _} = Session.sync_step(session, Flow.Message.answer())
    assert {:ok, %Session{current_mode: %{retries: ^retries}} = session, ReplyHelper.simple("Do you smoke?", "Do you smoke?"), _} = Session.sync_step(session, Flow.Message.answer())
    assert {:ok, %Session{current_mode: %{retries: ^retries}} = session, ReplyHelper.simple("Do you smoke?", "Do you smoke?"), _} = Session.sync_step(session, Flow.Message.answer())

    expected_session = %Session{
      current_mode: SessionModeProvider.new("mobileweb", channel, retries),
      fallback_mode: nil,
      flow: %Flow{questionnaire: quiz, mode: "mobileweb", current_step: 1}
    }

    assert session.current_mode == expected_session.current_mode
    assert session.fallback_mode == expected_session.fallback_mode
    assert session.flow.questionnaire == expected_session.flow.questionnaire
    assert session.flow.mode == expected_session.flow.mode
    assert session.flow.current_step == expected_session.flow.current_step

    step_result = Session.sync_step(session, Flow.Message.reply("No"))
    assert {:ok, session, ReplyHelper.simple("Do you exercise", "Do you exercise?", %{"Smokes" => "No"}), _} = step_result

    assert {:ok, %Session{current_mode: %{retries: ^retries}} = session, ReplyHelper.simple("Do you exercise", "Do you exercise?"), _} = Session.sync_step(session, Flow.Message.answer())
    assert {:ok, %Session{current_mode: %{retries: ^retries}} = session, ReplyHelper.simple("Do you exercise", "Do you exercise?"), _} = Session.sync_step(session, Flow.Message.answer())
    assert {:ok, %Session{current_mode: %{retries: ^retries}} = session, ReplyHelper.simple("Do you exercise", "Do you exercise?"), _} = Session.sync_step(session, Flow.Message.answer())

    expected_session = %Session{
      current_mode: SessionModeProvider.new("mobileweb", channel, retries),
      fallback_mode: nil,
      flow: %Flow{questionnaire: quiz, mode: "mobileweb", current_step: 3}
    }

    assert session.current_mode == expected_session.current_mode
    assert session.fallback_mode == expected_session.fallback_mode
    assert session.flow.questionnaire == expected_session.flow.questionnaire
    assert session.flow.mode == expected_session.flow.mode
    assert session.flow.current_step == expected_session.flow.current_step
    assert 1 == session.respondent.stats |> Stats.attempts(:mobileweb)
  end

  test "start with fallback delay", %{quiz: quiz, respondent: respondent, test_channel: test_channel, channel: channel} do
    {:ok, %{respondent: respondent} = session, _, timeout} = Session.start(quiz, respondent, channel, "sms", Schedule.always(), [], nil, nil, nil, 123)
    assert %Session{token: token} = session
    assert 123 = timeout
    assert token != nil

    assert_receive [:setup, ^test_channel, ^respondent, ^token]
    assert_receive [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]
  end

  test "start with channel without push", %{quiz: quiz, respondent: respondent} do
    test_channel = TestChannel.new
    channel = build(:channel, settings: test_channel |> TestChannel.settings)

    {:ok, %{respondent: respondent} = session, _, timeout} = Session.start(quiz, respondent, channel, "ivr", Schedule.always())

    assert %Session{token: token} = session
    assert 10 = timeout
    assert token != nil

    assert_receive [:setup, ^test_channel, ^respondent, ^token]
    refute_receive _

    assert session.channel_state == 0
    assert 1 == respondent.stats |> Stats.attempts(:ivr)
  end

  test "retry question", %{quiz: quiz, respondent: respondent, test_channel: test_channel, channel: channel} do
    assert {:ok, session = %Session{token: token, respondent: respondent}, _, 5} = Session.start(quiz, respondent, channel, "sms", Schedule.always(), [5])
    assert 1 == respondent.stats |> Stats.attempts(:sms)
    assert_receive [:setup, ^test_channel, ^respondent, ^token]
    assert_receive [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    assert {:ok, session = %Session{token: token2, respondent: respondent}, _, 10} = Session.timeout(session)
    assert 2 == respondent.stats |> Stats.attempts(:sms)
    assert token2 != token
    assert_receive [:ask, ^test_channel, ^respondent, ^token2, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    assert {:stalled, _, _} = Session.timeout(session)
  end

  test "retry with IVR channel", %{quiz: quiz, respondent: respondent} do
    test_channel = TestChannel.new
    channel = build(:channel, settings: test_channel |> TestChannel.settings)

    {:ok, session = %Session{token: token, respondent: respondent}, _, 5} = Session.start(quiz, respondent, channel, "ivr", Schedule.always(), [5])
    assert 1 == respondent.stats |> Stats.attempts(:ivr)
    assert_receive [:setup, ^test_channel, ^respondent, ^token]

    assert {:ok, %Session{token: token2, respondent: respondent}, _, 10} = Session.timeout(session)
    assert 2 == respondent.stats |> Stats.attempts(:ivr)
    assert token2 != token
    assert_receive [:setup, ^test_channel, ^respondent, ^token2]
  end

  test "last retry", %{quiz: quiz, respondent: respondent, test_channel: test_channel, channel: channel} do
    {:ok, session = %Session{token: token, respondent: respondent}, _, 10} = Session.start(quiz, respondent, channel, "sms", Schedule.always())
    assert_receive [:setup, ^test_channel, ^respondent, ^token]
    assert_receive [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    assert {:stalled, _, _} = Session.timeout(session)
  end

  test "doesn't retry if has queued message" do
    quiz = insert(:questionnaire, steps: @dummy_steps)
    respondent = insert(:respondent)
    test_channel = TestChannel.new(true)
    channel = build(:channel, settings: test_channel |> TestChannel.settings)

    assert {:ok, session = %Session{token: token, respondent: respondent}, _, 5} = Session.start(quiz, respondent, channel, "sms", Schedule.always(), [5])
    assert_receive [:setup, ^test_channel, ^respondent, ^token]
    assert_receive [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    assert {:ok, ^session, %Reply{}, 5} = Session.timeout(session)
  end

  test "doesn't fail if it has a queued message" do
    quiz = insert(:questionnaire, steps: @dummy_steps)
    respondent = insert(:respondent)
    test_channel = TestChannel.new(true)
    channel = build(:channel, settings: test_channel |> TestChannel.settings)

    assert {:ok, session = %Session{token: token, respondent: respondent}, _, 10} = Session.start(quiz, respondent, channel, "sms", Schedule.always())
    assert_receive [:setup, ^test_channel, ^respondent, ^token]
    assert_receive [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    assert {:ok, ^session, %Reply{}, 10} = Session.timeout(session)
  end

  test "mark respondent as failed when failure notification arrives on last retry", %{quiz: quiz, respondent: respondent, channel: channel} do
    {:ok, session = %Session{}, _, 10} = Session.start(quiz, respondent, channel, "sms", Schedule.always())
    assert :failed = Session.channel_failed(session, 'failed')
  end

  test "ignore failure notification when channel fails but there are retries", %{quiz: quiz, respondent: respondent, channel: channel} do
    {:ok, session = %Session{}, _, 5} = Session.start(quiz, respondent, channel, "sms", Schedule.always(), [5])
    assert :ok = Session.channel_failed(session, 'failed')
  end

  test "ignore failure notification when channel fails but there is a fallback channel", %{quiz: quiz, respondent: respondent, channel: channel} do
    {:ok, session = %Session{}, _, 10} = Session.start(quiz, respondent, channel, "sms", Schedule.always(), [], channel, "sms")
    assert :ok = Session.channel_failed(session, 'failed')
  end

  # Primary SMS fallbacks to IVR
  test "switch to fallback after last retry", %{quiz: quiz, respondent: respondent, test_channel: test_channel, channel: channel} do
    fallback_runtime_channel = TestChannel.new
    fallback_channel = build(:channel, settings: fallback_runtime_channel |> TestChannel.settings, type: "ivr")
    fallback_retries = [5]

    {:ok, session = %Session{token: token, respondent: respondent}, _, 10} = Session.start(quiz, respondent, channel, "sms", Schedule.always(), [], fallback_channel, "ivr", fallback_retries)
    assert_receive [:setup, ^test_channel, ^respondent, ^token]
    assert_receive [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    expected_session = %Session{
      current_mode: SessionModeProvider.new("ivr", fallback_channel, fallback_retries),
      fallback_mode: nil,
      flow: %Flow{questionnaire: quiz, mode: fallback_channel.type, current_step: session.flow.current_step}
    }

    {:ok, result = %Session{token: token, respondent: respondent}, _, 5} = Session.timeout(session)
    assert_receive [:setup, ^fallback_runtime_channel, ^respondent, ^token]

    assert result.current_mode == expected_session.current_mode
    assert result.fallback_mode == expected_session.fallback_mode
    assert result.flow.questionnaire == expected_session.flow.questionnaire
    assert result.flow.mode == expected_session.flow.mode
    assert result.flow.current_step == expected_session.flow.current_step
  end

  # Primary SMS retries SMS and then fallbacks to IVR
  test "switch to fallback after specified time", %{quiz: quiz, respondent: respondent, test_channel: test_channel, channel: channel} do
    fallback_runtime_channel = TestChannel.new
    fallback_channel = build(:channel, settings: fallback_runtime_channel |> TestChannel.settings, type: "ivr")
    fallback_retries = [7]

    {:ok, session = %Session{token: token, respondent: respondent}, _, 2} = Session.start(quiz, respondent, channel, "sms", Schedule.always(), [2], fallback_channel, "ivr", fallback_retries)
    assert_receive [:setup, ^test_channel, ^respondent, ^token]
    assert_receive [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    expected_session = %Session{
      current_mode: SessionModeProvider.new("ivr", fallback_channel, fallback_retries),
      fallback_mode: nil,
      flow: %Flow{questionnaire: quiz, mode: fallback_channel.type, current_step: session.flow.current_step}
    }

    {_, session_after_retry, _, _} = Session.timeout(session)
    {:ok, result = %Session{token: token, respondent: respondent}, _, 7} = Session.timeout(session_after_retry)
    assert_receive [:setup, ^fallback_runtime_channel, ^respondent, ^token]

    assert result.current_mode == expected_session.current_mode
    assert result.fallback_mode == expected_session.fallback_mode
    assert result.flow.questionnaire == expected_session.flow.questionnaire
    assert result.flow.mode == expected_session.flow.mode
    assert result.flow.current_step == expected_session.flow.current_step
  end

  # Primary SMS retries SMS and then fallbacks to IVR
  test "switch to fallback after retrying twice", %{quiz: quiz, respondent: respondent, test_channel: test_channel, channel: channel} do
    fallback_runtime_channel = TestChannel.new
    fallback_channel = build(:channel, settings: fallback_runtime_channel |> TestChannel.settings, type: "ivr")
    fallback_retries = [5]

    {:ok, session = %Session{token: token, respondent: respondent}, _, 2} = Session.start(quiz, respondent, channel, "sms", Schedule.always(), [2, 3], fallback_channel, "ivr", fallback_retries)
    assert_receive [:setup, ^test_channel, ^respondent, ^token]
    assert_receive [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    expected_session = %Session{
      current_mode: SessionModeProvider.new("ivr", fallback_channel, fallback_retries),
      fallback_mode: nil,
      flow: %Flow{questionnaire: quiz, mode: fallback_channel.type, current_step: session.flow.current_step}
    }

    assert 1 == respondent.stats |> Stats.attempts(:sms)

    {:ok, session = %Session{token: token, respondent: respondent}, _, 3} = Session.timeout(session)
    refute_receive [:setup, _, _, _, _]
    assert_receive [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    assert 2 == respondent.stats |> Stats.attempts(:sms)

    {_, session_after_second_retry, _, _} = Session.timeout(session)
    {:ok, result = %Session{token: token, respondent: respondent}, _, 5} = Session.timeout(session_after_second_retry)
    assert_receive [:setup, ^fallback_runtime_channel, ^respondent, ^token]

    assert 1 == respondent.stats |> Stats.attempts(:ivr)

    assert result.current_mode == expected_session.current_mode
    assert result.fallback_mode == expected_session.fallback_mode
    assert result.flow.questionnaire == expected_session.flow.questionnaire
    assert result.flow.mode == expected_session.flow.mode
    assert result.flow.current_step == expected_session.flow.current_step
  end

  test "applies first pattern that matches when swtiching to fallback", %{quiz: quiz, channel: channel} do
    respondent = insert(:respondent, phone_number: "12 34", sanitized_phone_number: "1234")
    patterns = [
      %{"input" => "22XXXX", "output" => "5XXXX"},
      %{"input" => "XXXX", "output" => "4XXXX"},
      %{"input" => "XXXX", "output" => "5XXXX"}
    ]

    fallback_runtime_channel = TestChannel.new
    fallback_channel = build(:channel, settings: fallback_runtime_channel |> TestChannel.settings, type: "ivr", patterns: patterns)
    fallback_retries = [5]

    {:ok, session, _, _} = Session.start(quiz, respondent, channel, "sms", Schedule.always(), [], fallback_channel, "ivr", fallback_retries)
    {:ok, %{respondent: respondent}, _, _} = Session.timeout(session)

    assert respondent.sanitized_phone_number == "41234"
    assert (Respondent |> Repo.get(respondent.id)).sanitized_phone_number == "41234"
  end

  test "sanitized_phone_number remains the same when switching to fallback and channel has no patterns", %{quiz: quiz, channel: channel} do
    respondent = insert(:respondent, phone_number: "12 34", sanitized_phone_number: "1234")

    fallback_runtime_channel = TestChannel.new
    fallback_channel = build(:channel, settings: fallback_runtime_channel |> TestChannel.settings, type: "ivr", patterns: [])
    fallback_retries = [5]

    {:ok, session, _, _} = Session.start(quiz, respondent, channel, "sms", Schedule.always(), [], fallback_channel, "ivr", fallback_retries)
    {:ok, %{respondent: respondent}, _, _} = Session.timeout(session)

    assert (Respondent |> Repo.get(respondent.id)).sanitized_phone_number == "1234"
  end

  test "sanitized_phone_number remains the same when switching to fallback and no pattern matches", %{quiz: quiz, channel: channel} do
    respondent = insert(:respondent, phone_number: "12 34", sanitized_phone_number: "1234")
    patterns = [
      %{"input" => "22XXXX", "output" => "5XXXX"},
      %{"input" => "1234XXXX5", "output" => "5XXXX"},
      %{"input" => "XXX", "output" => "1XXX"}
    ]
    fallback_runtime_channel = TestChannel.new
    fallback_channel = build(:channel, settings: fallback_runtime_channel |> TestChannel.settings, type: "ivr", patterns: patterns)
    fallback_retries = [5]

    {:ok, session, _, _} = Session.start(quiz, respondent, channel, "sms", Schedule.always(), [], fallback_channel, "ivr", fallback_retries)
    {:ok, %{respondent: respondent}, _, _} = Session.timeout(session)

    assert (Respondent |> Repo.get(respondent.id)).sanitized_phone_number == "1234"
  end

  test "doesn't switch to fallback if there are queued messages", %{quiz: quiz, respondent: respondent} do
    test_channel = TestChannel.new(true, false)
    channel = build(:channel, settings: test_channel |> TestChannel.settings)

    fallback_runtime_channel = TestChannel.new
    fallback_channel = build(:channel, settings: fallback_runtime_channel |> TestChannel.settings, type: "ivr")
    fallback_retries = [5]

    {:ok, session = %Session{token: token, respondent: respondent}, _, 10} = Session.start(quiz, respondent, channel, "sms", Schedule.always(), [], fallback_channel, "ivr", fallback_retries)
    assert_receive [:setup, ^test_channel, ^respondent, ^token]
    assert_receive [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    assert {:ok, ^session, %Reply{}, 10} = Session.timeout(session)
  end

  test "doesn't consume a retry if it has an expired message" do
    quiz = insert(:questionnaire, steps: @dummy_steps)
    respondent = insert(:respondent)
    test_channel = TestChannel.new(:expired)
    channel = build(:channel, settings: test_channel |> TestChannel.settings)

    assert {:ok, session = %Session{token: token, respondent: respondent}, _, 5} = Session.start(quiz, respondent, channel, "ivr", Schedule.always(), [5])
    assert 1 == respondent.stats |> Stats.attempts(:ivr)

    assert_receive [:setup, ^test_channel, ^respondent, ^token]

    assert {:ok, %Session{token: token, respondent: respondent}, %Reply{}, 5} = Session.timeout(session)
    assert 1 == respondent.stats |> Stats.attempts(:ivr)
    assert_receive [:setup, ^test_channel, ^respondent, ^token]
  end

  test "doesn't fail if it has an expired message" do
    quiz = insert(:questionnaire, steps: @dummy_steps)
    respondent = insert(:respondent)
    test_channel = TestChannel.new(:expired)
    channel = build(:channel, settings: test_channel |> TestChannel.settings, type: "ivr")

    assert {:ok, session = %Session{token: token, respondent: respondent}, _, 10} = Session.start(quiz, respondent, channel, "ivr", Schedule.always())
    assert_receive [:setup, ^test_channel, ^respondent, ^token]

    assert {:ok, %Session{token: token, respondent: respondent}, %Reply{}, 10} = Session.timeout(session)
    assert_receive [:setup, ^test_channel, ^respondent, ^token]
  end

  test "doesn't switch to fallback if it has an expired message", %{quiz: quiz, respondent: respondent} do
    test_channel = TestChannel.new(:expired)
    channel = build(:channel, settings: test_channel |> TestChannel.settings)

    fallback_runtime_channel = TestChannel.new
    fallback_channel = build(:channel, settings: fallback_runtime_channel |> TestChannel.settings, type: "ivr")
    fallback_retries = [5]

    {:ok, session = %Session{token: token, respondent: respondent}, _, 10} = Session.start(quiz, respondent, channel, "ivr", Schedule.always(), [], fallback_channel, "ivr", fallback_retries)
    assert 1 == respondent.stats |> Stats.attempts(:ivr)
    assert_receive [:setup, ^test_channel, ^respondent, ^token]

    assert {:ok, %Session{token: token, respondent: respondent}, %Reply{}, 10} = Session.timeout(session)
    assert 1 == respondent.stats |> Stats.attempts(:ivr)
    assert_receive [:setup, ^test_channel, ^respondent, ^token]
  end

  test "uses retry configuration", %{quiz: quiz, respondent: respondent, channel: channel} do
    assert {:ok, _, _, 60} = Session.start(quiz, respondent, channel, "sms", Schedule.always(), [60])
  end

  test "step", %{quiz: quiz, respondent: respondent, channel: channel} do
    {:ok, session, _, _} = Session.start(quiz, respondent, channel, "sms", Schedule.always())

    step_result = Session.sync_step(session, Flow.Message.reply("N"))
    assert {:ok, %Session{}, ReplyHelper.simple("Do you exercise", "Do you exercise? Reply 1 for YES, 2 for NO", %{"Smokes" => "No"}), 10} = step_result

    assert [response] = respondent |> Ecto.assoc(:responses) |> Ask.Repo.all
    assert response.field_name == "Smokes"
    assert response.value == "No"
  end

  test "end", %{quiz: quiz, respondent: respondent, channel: channel} do
    {:ok, session, _, _} = Session.start(quiz, respondent, channel, "sms", Schedule.always())

    {:ok, session, _, _} = Session.sync_step(session, Flow.Message.reply("Y"))
    {:ok, session, _, _} = Session.sync_step(session, Flow.Message.reply("N"))
    {:ok, session, _, _} = Session.sync_step(session, Flow.Message.reply("99"))
    {:end, _, _} = Session.sync_step(session, Flow.Message.reply("11"))

    responses = respondent
    |> Ecto.assoc(:responses)
    |> Ecto.Query.order_by(:id)
    |> Ask.Repo.all

    assert [
      %{field_name: "Smokes", value: "Yes"},
      %{field_name: "Exercises", value: "No"},
      %{field_name: "Perfect Number", value: "99"},
      %{field_name: "Question", value: "11"},
      ] = responses
  end

  test "steps with the same variable overrides previous value", %{respondent: respondent, channel: channel} do
    quiz = insert(:questionnaire, steps: @steps_with_duplicate_store)
    {:ok, session, _, _} = Session.start(quiz, respondent, channel, "sms", Schedule.always())

    {:ok, session, _, _} = Session.sync_step(session, Flow.Message.reply("Y"))
    {:end, _, _} = Session.sync_step(session, Flow.Message.reply("N"))

    responses = respondent
    |> Ecto.assoc(:responses)
    |> Ask.Repo.all

    assert [
      %{field_name: "Smokes", value: "Yes"}
    ] = responses
  end

  test "ends when quota is reached at leaf", %{quiz: quiz, respondent: respondent, channel: channel, test_channel: test_channel} do
    survey = respondent.survey

    quotas = %{
      "vars" => ["Smokes", "Exercises"],
      "buckets" => [
        %{
          "condition" => [%{"store" => "Smokes", "value" => "No"}, %{"store" => "Exercises", "value" => "No"}],
          "quota" => 1,
          "count" => 1
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

    survey
    |> Repo.preload([:quota_buckets])
    |> Survey.changeset(%{quotas: quotas})
    |> Repo.update!

    respondent = Respondent |> Repo.get(respondent.id)

    {:ok, session = %Session{token: token, respondent: respondent}, _, _} = Session.start(quiz, respondent, channel, "sms", Schedule.always())
    assert_receive [:setup, ^test_channel, ^respondent, ^token]

    {:ok, session, _, _} = Session.sync_step(session, Flow.Message.reply("N"))
    assert_receive [:ask, ^test_channel, ^respondent, ^token, ReplyHelper.simple("Do you smoke?", "Do you smoke? Reply 1 for YES, 2 for NO")]

    assert {:rejected, %{steps: [%{prompts: ["Quota completed"]}]}, _} = Session.sync_step(session, Flow.Message.reply("N"))

    # The session won't update the respondent, the broker will
    respondent = Respondent |> Repo.get(respondent.id)
    assert respondent.state == "pending"
    assert respondent.disposition == "registered"
    assert 1 == respondent.stats |> Stats.attempts(:sms)
  end

  test "ends when quota is reached at leaf, with more stores", %{quiz: quiz, respondent: respondent, channel: channel} do
    survey = respondent.survey

    quotas = %{
      "vars" => ["Exercises"],
      "buckets" => [
        %{
          "condition" => [%{"store" => "Exercises","value" => "No"}],
          "quota" => 1,
          "count" => 1
        },
        %{
          "condition" => [%{"store" => "Exercises","value" => "Yes"}],
          "quota" => 2,
          "count" => 0
        },
      ]
    }

    survey
    |> Repo.preload([:quota_buckets])
    |> Survey.changeset(%{quotas: quotas})
    |> Repo.update!

    respondent = Respondent |> Repo.get(respondent.id)

    {:ok, session, _, _} = Session.start(quiz, respondent, channel, "sms", Schedule.always())
    {:ok, session, _, _} = Session.sync_step(session, Flow.Message.reply("N"))
    assert {:rejected, %{steps: [%{prompts: ["Quota completed"]}]}, _} = Session.sync_step(session, Flow.Message.reply("N"))
  end

  test "ends when quota is reached at leaf, numeric", %{quiz: quiz, respondent: respondent, channel: channel} do
    survey = respondent.survey

    quotas = %{
      "vars" => ["Smokes", "Perfect Number"],
      "buckets" => [
        %{
          "condition" => [%{"store" => "Smokes", "value" => "No"},
                          %{"store" => "Perfect Number", "value" => [20, 30]}],
          "quota" => 1,
          "count" => 1
        },
        %{
          "condition" => [%{"store" => "Smokes", "value" => "No"},
                          %{"store" => "Perfect Number", "value" => [31, 40]}],
          "quota" => 2,
          "count" => 0
        },
        %{
          "condition" => [%{"store" => "Smokes", "value" => "Yes"},
                          %{"store" => "Perfect Number", "value" => [20, 30]}],
          "quota" => 1,
          "count" => 0
        },
        %{
          "condition" => [%{"store" => "Smokes", "value" => "Yes"},
                          %{"store" => "Perfect Number", "value" => [31, 40]}],
          "quota" => 2,
          "count" => 0
        },
      ]
    }

    survey
    |> Repo.preload([:quota_buckets])
    |> Survey.changeset(%{quotas: quotas})
    |> Repo.update!

    respondent = Respondent |> Repo.get(respondent.id)

    {:ok, session, _, _} = Session.start(quiz, respondent, channel, "sms", Schedule.always())
    {:ok, session, _, _} = Session.sync_step(session, Flow.Message.reply("N"))
    {:ok, session, _, _} = Session.sync_step(session, Flow.Message.reply("Y"))
    assert {:rejected, %{steps: [%{prompts: ["Quota completed"]}]}, _} = Session.sync_step(session, Flow.Message.reply("25"))
  end

  test "accepts respondent in bucket upper bound", %{quiz: quiz, respondent: respondent, channel: channel} do
    survey = respondent.survey

    quotas = %{
      "vars" => ["Perfect Number"],
      "buckets" => [
        %{
          "condition" => [%{"store" => "Perfect Number", "value" => [18, 29]}],
          "quota" => 1,
          "count" => 0
        },
        %{
          "condition" => [%{"store" => "Perfect Number", "value" => [30, 79]}],
          "quota" => 1,
          "count" => 0
        },
        %{
          "condition" => [%{"store" => "Perfect Number", "value" => [80, 120]}],
          "quota" => 1,
          "count" => 0
        },
      ]
    }

    survey
    |> Repo.preload([:quota_buckets])
    |> Survey.changeset(%{quotas: quotas})
    |> Repo.update!

    respondent = Respondent |> Repo.get(respondent.id)

    {:ok, session, _, _, _} = Session.start(quiz, respondent, channel, "sms", Schedule.always())
    {:ok, session, _, _, _} = Session.sync_step(session, Flow.Message.reply("N"))
    {:ok, session, _, _, _} = Session.sync_step(session, Flow.Message.reply("Y"))
    {:ok, _, %{stores: %{"Perfect Number" => "120"}}, _, _} = Session.sync_step(session, Flow.Message.reply("120"))
  end

  test "ends only after completing the quota questions", %{quiz: quiz, respondent: respondent, channel: channel} do
    survey = respondent.survey

    quotas = %{
      "vars" => ["Smokes", "Exercises"],
      "buckets" => [
        %{
          "condition" => [%{"store" => "Smokes", "value" => "No"},
                          %{"store" => "Exercises", "value" => "No"}],
          "quota" => 1,
          "count" => 1
        },
        %{
          "condition" => [%{"store" => "Smokes", "value" => "No"},
                          %{"store" => "Exercises", "value" => "Yes"}],
          "quota" => 2,
          "count" => 2
        },
        %{
          "condition" => [%{"store" => "Smokes", "value" => "Yes"},
                          %{"store" => "Exercises", "value" => "No"}],
          "quota" => 3,
          "count" => 0
        },
        %{
          "condition" => [%{"store" => "Smokes", "value" => "Yes"},
                          %{"store" => "Exercises", "value" => "Yes"}],
          "quota" => 4,
          "count" => 0
        },
      ]
    }

    survey
    |> Repo.preload([:quota_buckets])
    |> Survey.changeset(%{quotas: quotas})
    |> Repo.update!

    respondent = Respondent |> Repo.get(respondent.id)

    {:ok, session, _, _} = Session.start(quiz, respondent, channel, "sms", Schedule.always())

    step_result = Session.sync_step(session, Flow.Message.reply("N"))
    assert {:ok, session, ReplyHelper.simple("Do you exercise", "Do you exercise? Reply 1 for YES, 2 for NO", %{"Smokes" => "No"}), 10} = step_result

    respondent = Respondent |> Repo.get(respondent.id)
    assert respondent.quota_bucket_id == nil

    assert {:rejected, %{steps: [%{prompts: ["Quota completed"]}]}, _} = Session.sync_step(session, Flow.Message.reply("Y"))
    respondent = Respondent |> Repo.get(respondent.id)

    qb2 = (from q in QuotaBucket, where: q.quota == 2) |> Repo.one
    assert respondent.quota_bucket_id == qb2.id
  end

  test "ends only after completing the quota numeric questions", %{quiz: quiz, respondent: respondent, channel: channel} do
    survey = respondent.survey

    quotas = %{
      "vars" => ["Smokes", "Perfect Number"],
      "buckets" => [
        %{
          "condition" => [%{"store" => "Smokes", "value" => "Yes"},
                          %{"store" => "Perfect Number", "value" => [18,29]}],
          "quota" => 1,
          "count" => 1
        },
        %{
          "condition" => [%{"store" => "Smokes", "value" => "No"},
                          %{"store" => "Perfect Number", "value" => [18,29]}],
          "quota" => 2,
          "count" => 2
        }
      ]
    }

    survey
    |> Repo.preload([:quota_buckets])
    |> Survey.changeset(%{quotas: quotas})
    |> Repo.update!

    respondent = Respondent |> Repo.get(respondent.id)

    {:ok, session, _, _} = Session.start(quiz, respondent, channel, "sms", Schedule.always())

    step_result = Session.sync_step(session, Flow.Message.reply("N"))
    assert {:ok, session, ReplyHelper.simple("Do you exercise", "Do you exercise? Reply 1 for YES, 2 for NO", %{"Smokes" => "No"}), 10} = step_result

    respondent = Respondent |> Repo.get(respondent.id)
    assert respondent.quota_bucket_id == nil

    step_result = Session.sync_step(session, Flow.Message.reply("Y"))
    assert {:ok, session, ReplyHelper.simple("Which is the second perfect number?", "Which is the second perfect number??", %{"Exercises" => "Yes"}), 10} = step_result

    assert {:rejected, %{steps: [%{prompts: ["Quota completed"]}]}, _} = Session.sync_step(session, Flow.Message.reply("20"))
    respondent = Respondent |> Repo.get(respondent.id)

    qb2 = (from q in QuotaBucket, where: q.quota == 2) |> Repo.one
    assert respondent.quota_bucket_id == qb2.id
  end

  test "assigns respondent to its bucket", %{quiz: quiz, respondent: respondent, channel: channel} do
    survey = respondent.survey

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

    survey
    |> Repo.preload([:quota_buckets])
    |> Survey.changeset(%{quotas: quotas})
    |> Repo.update!

    qb2 = (from q in QuotaBucket, where: q.quota == 2) |> Repo.one

    respondent = Respondent |> Repo.get(respondent.id)
    assert respondent.quota_bucket_id == nil

    {:ok, session, _, _} = Session.start(quiz, respondent, channel, "sms", Schedule.always())

    {:ok, session, _, _} = Session.sync_step(session, Flow.Message.reply("N"))
    respondent = Respondent |> Repo.get(respondent.id)
    assert respondent.quota_bucket_id == nil

    Session.sync_step(session, Flow.Message.reply("Y"))
    respondent = Respondent |> Repo.get(respondent.id)
    assert respondent.quota_bucket_id == qb2.id
  end

  test "assigns respondent to its bucket, with more responses", %{quiz: quiz, respondent: respondent, channel: channel} do
    survey = respondent.survey

    quotas = %{
      "vars" => ["Exercises"],
      "buckets" => [
        %{
          "condition" => [%{"store" => "Exercises", "value" => "No"}],
          "quota" => 1,
          "count" => 0
        },
        %{
          "condition" => [%{"store" => "Exercises", "value" => "Yes"}],
          "quota" => 2,
          "count" => 0
        },
      ]
    }

    survey
    |> Repo.preload([:quota_buckets])
    |> Survey.changeset(%{quotas: quotas})
    |> Repo.update!

    qb2 = (from q in QuotaBucket, where: q.quota == 2) |> Repo.one

    respondent = Respondent |> Repo.get(respondent.id)
    assert respondent.quota_bucket_id == nil

    {:ok, session, _, _} = Session.start(quiz, respondent, channel, "sms", Schedule.always())

    {:ok, session, _, _} = Session.sync_step(session, Flow.Message.reply("N"))
    respondent = Respondent |> Repo.get(respondent.id)
    assert respondent.quota_bucket_id == nil

    Session.sync_step(session, Flow.Message.reply("Y"))
    respondent = Respondent |> Repo.get(respondent.id)
    assert respondent.quota_bucket_id == qb2.id
  end

  test "assigns respondent to its bucket, numeric condition", %{quiz: quiz, respondent: respondent, channel: channel} do
    survey = respondent.survey

    quotas = %{
      "vars" => ["Smokes", "Exercises"],
      "buckets" => [
        %{
          "condition" => [%{"store" => "Smokes", "value" => "No"},
                          %{"store" => "Perfect Number", "value" => [20, 30]}],
          "quota" => 1,
          "count" => 0
        },
        %{
          "condition" => [%{"store" => "Smokes", "value" => "No"},
                          %{"store" => "Perfect Number", "value" => [31, 40]}],
          "quota" => 2,
          "count" => 0
        },
        %{
          "condition" => [%{"store" => "Smokes", "value" => "Yes"},
                          %{"store" => "Perfect Number", "value" => [20, 30]}],
          "quota" => 3,
          "count" => 0
        },
        %{
          "condition" => [%{"store" => "Smokes", "value" => "Yes"},
                          %{"store" => "Perfect Number", "value" => [31, 40]}],
          "quota" => 4,
          "count" => 0
        },
      ]
    }

    survey
    |> Repo.preload([:quota_buckets])
    |> Survey.changeset(%{quotas: quotas})
    |> Repo.update!

    qb2 = (from q in QuotaBucket, where: q.quota == 2) |> Repo.one

    respondent = Respondent |> Repo.get(respondent.id)
    assert respondent.quota_bucket_id == nil

    {:ok, session, _, _} = Session.start(quiz, respondent, channel, "sms", Schedule.always())

    {:ok, session, _, _} = Session.sync_step(session, Flow.Message.reply("N"))
    respondent = Respondent |> Repo.get(respondent.id)
    assert respondent.quota_bucket_id == nil

    {:ok, session, _, _} = Session.sync_step(session, Flow.Message.reply("Y"))
    respondent = Respondent |> Repo.get(respondent.id)
    assert respondent.quota_bucket_id == nil

    {:ok, _session, _, _} = Session.sync_step(session, Flow.Message.reply("33"))
    respondent = Respondent |> Repo.get(respondent.id)
    assert respondent.quota_bucket_id == qb2.id
  end

  test "flag with prompt", %{respondent: respondent, channel: channel} do
    quiz = insert(:questionnaire, steps: @flag_steps)
    {:ok, _, %{disposition: disposition}, _} = Session.start(quiz, respondent, channel, "sms", Schedule.always())

    assert disposition == "interim partial"
  end

  test "flag and end", %{respondent: respondent, channel: channel} do
    quiz = build(:questionnaire, steps: @partial_step)
    {:end, %{disposition: disposition}, respondent} = Session.start(quiz, respondent, channel, "sms", Schedule.always())

    assert disposition == "interim partial"
    assert 1 == respondent.stats |> Stats.attempts(:sms)
  end

  describe "creates survey log entries when disposition changes" do
    test "log disposition_changed after logging the response", %{respondent: respondent} do
      {:ok, survey_logger} = SurveyLogger.start_link
      quiz = insert(:questionnaire, steps: @flag_step_after_multiple_choice)
      ivr_channel = insert(:channel, settings: TestChannel.new |> TestChannel.settings, type: "ivr")
      # respondent is updated to "queued" in order to ensure a valid disposition transition "queued" -> "interim partial"
      respondent = respondent |> Respondent.changeset(%{disposition: "started"}) |> Repo.update!
      {:ok, session, _, _} = Session.start(quiz, respondent, ivr_channel, "ivr", Schedule.always())
      Session.sync_step(session, Flow.Message.reply("1"))

      survey_logger |> GenServer.stop
      entries = SurveyLogEntry |> Repo.all
      response_index = entries |> Enum.find_index(fn e -> e.action_type == "response" end)

      response_entry = entries |> Enum.at(response_index)
      assert response_entry.action_type == "response"
      assert response_entry.disposition == "started"
      assert response_entry.action_data == "1"

      disposition_changed_entry = entries |> Enum.at(response_index + 1)
      assert disposition_changed_entry.action_type == "disposition changed"
      assert disposition_changed_entry.action_data == "Interim partial"
      assert disposition_changed_entry.disposition == "started"

      prompt_entry = entries |> Enum.at(response_index + 2)
      assert prompt_entry.action_type == "prompt"
      assert prompt_entry.action_data == "Is this the last question?"
      assert prompt_entry.disposition == "interim partial"
    end

    test "log disposition_changed after answering a call", %{respondent: respondent} do
      {:ok, survey_logger} = SurveyLogger.start_link
      quiz = insert(:questionnaire, steps: @flag_step_after_multiple_choice)
      ivr_channel = insert(:channel, settings: TestChannel.new |> TestChannel.settings, type: "ivr")
      # respondent disposition is updated to "queued",
      # representing a respondent that has already been started.
      respondent = respondent |> Respondent.changeset(%{disposition: "queued"}) |> Repo.update!
      {:ok, session, _, _} = Session.start(quiz, respondent, ivr_channel, "ivr", Schedule.always())

      Session.sync_step(session, Flow.Message.answer())

      survey_logger |> GenServer.stop
      entries = SurveyLogEntry |> Repo.all

      second_entry = entries |> Enum.at(1)
      assert second_entry.action_type == "contact"
      assert second_entry.action_data == "Answer"
      third_entry = entries |> Enum.at(2)
      assert third_entry.action_type == "disposition changed"
      assert third_entry.disposition == "queued"
      assert third_entry.action_data == "Contacted"
      fourth_entry = entries |> Enum.at(3)
      assert fourth_entry.action_type == "prompt"
      assert fourth_entry.disposition == "contacted"
      assert fourth_entry.action_data == "Do you exercise?"
    end
  end
end
