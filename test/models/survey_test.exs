defmodule Ask.SurveyTest do
  use Ask.ModelCase
  use Ask.TestHelpers
  use Ask.MockTime

  alias Ask.{Survey, Schedule, TimeMock, Repo}

  @valid_attrs %{name: "some content", schedule: Schedule.default()}
  @invalid_attrs %{}

  test "changeset with valid attributes" do
    changeset = Survey.changeset(%Survey{project_id: 0}, @valid_attrs)
    assert changeset.valid?
  end

  test "changeset with invalid attributes" do
    changeset = Survey.changeset(%Survey{}, @invalid_attrs)
    refute changeset.valid?
  end

  test "default retries configuration" do
    survey = %Survey{}
    assert [] = Survey.retries_configuration(survey, "sms")
  end

  test "parse retries configuration" do
    survey = %Survey{sms_retry_configuration: "10m 2h 3d"}
    assert [10, 120, 4320] = Survey.retries_configuration(survey, "sms")
  end

  test "handle invalid retries configuration" do
    survey = %Survey{sms_retry_configuration: "10m foo . 2 1h"}
    assert [10, 60] = Survey.retries_configuration(survey, "sms")
  end

  test "parse fallback delay" do
    survey = %Survey{fallback_delay: "2h"}
    assert Survey.fallback_delay(survey) == 120
  end

  test "returns default fallback delay" do
    survey = %Survey{}
    assert Survey.fallback_delay(survey) == Survey.default_fallback_delay()
  end

  test "returns nil fallback delay on parse failure" do
    survey = %Survey{fallback_delay: "foo"}
    assert Survey.fallback_delay(survey) == nil
  end

  test "default changeset includes a non-nil FLOIP package id" do
    changeset = Survey.changeset(%Survey{})
    assert get_field(changeset, :floip_package_id) != nil
  end

  test "default changeset does not override FLOIP package id" do
    changeset = Survey.changeset(%Survey{floip_package_id: "foo"})
    assert get_field(changeset, :floip_package_id) == "foo"
  end

  test "survey has FLOIP package if it is running" do
    survey = %Survey{state: "running"}
    assert length(survey |> Survey.packages()) == 1
  end

  test "survey has FLOIP package if it is terminated" do
    survey = %Survey{state: "terminated"}
    assert length(survey |> Survey.packages()) == 1
  end

  test "survey does not have FLOIP package unless it is running or terminated" do
    # Because its underlying questionnaire may still change
    survey = %Survey{state: "foo"}
    assert length(survey |> Survey.packages()) == 0
  end

  test "changeset with description" do
    changeset = %Survey{} |> Survey.changeset(%{project_id: 5, description: "initial survey"})
    assert changeset.valid?
    assert changeset.changes.description == "initial survey"
  end

  test "default changeset does not set ended_at field" do
    changeset = Survey.changeset(%Survey{})
    assert is_nil(get_field(changeset, :ended_at))
  end

  @tag :time_mock
  test "changeset with terminated state has ended_at field set" do
    test_now = Timex.now
    TimeMock
    |> expect(:now, fn () -> test_now end)

    changeset = Survey.changeset(%Survey{state: "terminated"})
    assert get_field(changeset, :ended_at) == test_now
  end

  test "enumerates channels of running surveys" do
    surveys = [
      insert(:survey, state: "pending"),
      insert(:survey, state: "running")
    ]

    channels = [
      insert(:channel),
      insert(:channel)
    ]

    setup_surveys_with_channels(surveys, channels)

    running_channels =
      Survey.running_channels()
      |> Enum.map(fn c -> c.id end)
      |> Enum.sort()

    assert running_channels == [Enum.at(channels, 1).id]
  end

  test "enumerates channels of a survey" do
    survey = insert(:survey)
    channel_1 = insert(:channel)
    channel_2 = insert(:channel)
    channel_3 = insert(:channel)
    group_1 = insert(:respondent_group, survey: survey)
    group_2 = insert(:respondent_group, survey: survey)
    insert(:respondent_group_channel, channel: channel_1, respondent_group: group_1, mode: "sms")
    insert(:respondent_group_channel, channel: channel_2, respondent_group: group_1, mode: "sms")
    insert(:respondent_group_channel, channel: channel_3, respondent_group: group_2, mode: "sms")
    survey = survey |> Repo.preload(respondent_groups: [respondent_group_channels: :channel])

    survey_channels_ids = Survey.survey_channels(survey) |> Enum.map(& &1.id)

    assert survey_channels_ids == [channel_1.id, channel_2.id, channel_3.id]
  end

  # TODO: Write tests!
  describe "expired?" do
    test "it works"
  end
end
