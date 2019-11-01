defmodule Ask.SurveyTest do
  use Ask.ModelCase
  use Ask.TestHelpers

  alias Ask.Survey

  @valid_attrs %{name: "some content", schedule: Ask.Schedule.default()}
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
    survey = %Survey{sms_retry_configuration: "5m 2h 3d"}
    assert [5, 120, 4320] = Survey.retries_configuration(survey, "sms")
  end

  test "handle invalid retries configuration" do
    survey = %Survey{sms_retry_configuration: "5m foo . 2 1h"}
    assert [5, 60] = Survey.retries_configuration(survey, "sms")
  end

  test "parse fallback delay" do
    survey = %Survey{fallback_delay: "2h"}
    assert Survey.fallback_delay(survey) == 120
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
    assert length(survey |> Survey.packages) == 1
  end

  test "survey has FLOIP package if it is terminated" do
    survey = %Survey{state: "terminated"}
    assert length(survey |> Survey.packages) == 1
  end

  test "survey does not have FLOIP package unless it is running or terminated" do
    # Because its underlying questionnaire may still change
    survey = %Survey{state: "foo"}
    assert length(survey |> Survey.packages) == 0
  end

  test "changeset with description" do
    changeset = %Survey{} |> Survey.changeset(%{project_id: 5, description: "initial survey"})
    assert changeset.valid?
    assert changeset.changes.description == "initial survey"
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
      |> Enum.sort

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
    survey = survey |> Ask.Repo.preload(respondent_groups: [respondent_group_channels: :channel])

    survey_channels_ids = Survey.survey_channels(survey) |> Enum.map(&(&1.id))

    assert survey_channels_ids == [channel_1.id, channel_2.id, channel_3.id]
  end

  describe "retries histogram" do
    test "flow with no retries" do
      mode = ["sms"]
      survey = insert(:survey)
      %{flow: flow} = survey |> Survey.retries_histogram(mode)

      assert flow == [%{type: "sms", delay: 0}]
    end

    test "flow with no fallbacks" do
      mode = ["sms"]
      survey = insert(:survey, %{sms_retry_configuration: "1h 2h 3h"})
      %{flow: flow} = survey |> Survey.retries_histogram(mode)

      assert flow == [%{type: "sms", delay: 0}, %{type: "sms", delay: 1, label: "1h"}, %{type: "sms", delay: 2, label: "2h"}, %{type: "sms", delay: 3, label: "3h"}]
    end

    test "flow with 1 fallback" do
      mode = ["sms", "ivr"]
      survey = insert(:survey, %{sms_retry_configuration: "1h 2h 3h", ivr_retry_configuration: "5h 6h 7h", fallback_delay: "4h"})
      %{flow: flow} = survey |> Survey.retries_histogram(mode)

      assert flow == [
        %{type: "sms", delay: 0}, %{type: "sms", delay: 1, label: "1h"}, %{type: "sms", delay: 2, label: "2h"}, %{type: "sms", delay: 3, label: "3h"},
        %{type: "ivr", delay: 4, label: "4h"}, %{type: "ivr", delay: 5, label: "5h"}, %{type: "ivr", delay: 6, label: "6h"}, %{type: "ivr", delay: 7, label: "7h"}
      ]
    end

    test "flow with 2 fallbacks" do
      mode = ["mobileweb", "ivr", "sms"]
      survey = insert(:survey, %{sms_retry_configuration: "1h 2h 3h", ivr_retry_configuration: "5h 6h 7h", mobileweb_retry_configuration: "2h 5h 8h", fallback_delay: "4h"})
      %{flow: flow} = survey |> Survey.retries_histogram(mode)

      assert flow == [
        %{type: "mobileweb", delay: 0}, %{type: "mobileweb", delay: 2, label: "2h"}, %{type: "mobileweb", delay: 5, label: "5h"}, %{type: "mobileweb", delay: 8, label: "8h"},
        %{type: "ivr", delay: 4,
         label: "4h"}, %{type: "ivr", delay: 5, label: "5h"}, %{type: "ivr", delay: 6, label: "6h"}, %{type: "ivr", delay: 7, label: "7h"},
        %{type: "sms", delay: 4, label: "4h"}, %{type: "sms", delay: 1, label: "1h"}, %{type: "sms", delay: 2, label: "2h"}, %{type: "sms", delay: 3, label: "3h"}
      ]
    end
  end
end
