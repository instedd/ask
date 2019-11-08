defmodule Ask.SurveyTest do
  use Ask.ModelCase
  use Ask.TestHelpers

  alias Ask.{Survey, RetryStat}

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

      assert flow == [
               %{type: "sms", delay: 0},
               %{type: "sms", delay: 1, label: "1h"},
               %{type: "sms", delay: 2, label: "2h"},
               %{type: "sms", delay: 3, label: "3h"}
             ]
    end

    test "flow with 1 fallback" do
      mode = ["sms", "ivr"]

      survey =
        insert(:survey, %{
          sms_retry_configuration: "1h 2h 3h",
          ivr_retry_configuration: "5h 6h 7h",
          fallback_delay: "4h"
        })

      %{flow: flow} = survey |> Survey.retries_histogram(mode)

      assert flow == [
               %{type: "sms", delay: 0},
               %{type: "sms", delay: 1, label: "1h"},
               %{type: "sms", delay: 2, label: "2h"},
               %{type: "sms", delay: 3, label: "3h"},
               %{type: "ivr", delay: 4, label: "4h"},
               %{type: "ivr", delay: 5, label: "5h"},
               %{type: "ivr", delay: 6, label: "6h"},
               %{type: "ivr", delay: 7, label: "7h"}
             ]
    end

    test "flow with 2 fallbacks" do
      mode = ["mobileweb", "ivr", "sms"]

      survey =
        insert(:survey, %{
          sms_retry_configuration: "1h 2h 3h",
          ivr_retry_configuration: "5h 6h 7h",
          mobileweb_retry_configuration: "2h 5h 8h",
          fallback_delay: "4h"
        })

      %{flow: flow} = survey |> Survey.retries_histogram(mode)

      assert flow == [
               %{type: "mobileweb", delay: 0},
               %{type: "mobileweb", delay: 2, label: "2h"},
               %{type: "mobileweb", delay: 5, label: "5h"},
               %{type: "mobileweb", delay: 8, label: "8h"},
               %{type: "ivr", delay: 4, label: "4h"},
               %{type: "ivr", delay: 5, label: "5h"},
               %{type: "ivr", delay: 6, label: "6h"},
               %{type: "ivr", delay: 7, label: "7h"},
               %{type: "sms", delay: 4, label: "4h"},
               %{type: "sms", delay: 1, label: "1h"},
               %{type: "sms", delay: 2, label: "2h"},
               %{type: "sms", delay: 3, label: "3h"}
             ]
    end

    test "actives 1 mode no retries no respondents" do
      test_actives_no_retries_no_respondent("sms")
      test_actives_no_retries_no_respondent("ivr")
      test_actives_no_retries_no_respondent("mobileweb")
    end

    test "actives 1 mode no retries 1 respondent" do
      test_actives_no_retries_1_respondent("sms")
      test_actives_no_retries_1_respondent("ivr")
      test_actives_no_retries_1_respondent("mobileweb")
    end

    test "actives 1 mode 1 retry no respondents" do
      test_actives_1_retry_no_respondents("sms")
      test_actives_1_retry_no_respondents("ivr")
      test_actives_1_retry_no_respondents("mobileweb")
    end

    test "actives 1 mode 1 retry 1 active respondent in 1st attempt" do
      test_actives_1_retry_1_respondent("sms", 1, 0)
      test_actives_1_retry_1_respondent("ivr", 1, 0)
      test_actives_1_retry_1_respondent("mobileweb", 1, 0)
    end

    test "actives 1 mode 1 retry 1 active respondent in 2nd attempt" do
      test_actives_1_retry_1_respondent("sms", 2, 2)
      test_actives_1_retry_1_respondent("ivr", 2, 2)
      test_actives_1_retry_1_respondent("mobileweb", 2, 2)
    end

    test "actives 1 mode 1 retry 1 waiting respondent for 2nd attempt" do
      test_actives_1_retry_1_respondent_waiting("sms")
      test_actives_1_retry_1_respondent_waiting("ivr")
      test_actives_1_retry_1_respondent_waiting("mobileweb")
    end

    test "actives 1 mode 2 retries 4 active 2 waiting respondents" do
      test_actives_2_retries_6_respondents("sms")
      test_actives_2_retries_6_respondents("ivr")
      test_actives_2_retries_6_respondents("mobileweb")
    end

    test "actives sms with 1 retry, 1 active and 2 overdue in 2nd attempt" do
      test_actives_2_overdue("sms")
      test_actives_2_overdue("ivr")
      test_actives_2_overdue("mobileweb")
    end

    test "actives sms -> ivr with no retries 1 respondent" do
      mode = ["sms", "ivr"]
      survey = insert(:survey, %{fallback_delay: "2h"})
      retry_time = Timex.now() |> RetryStat.retry_time()
      %{attempt: 1, mode: mode, retry_time: retry_time, survey_id: survey.id}
        |> increase_stat(1)

      %{actives: actives} = survey |> Survey.retries_histogram(mode)

      assert actives == [%{hour: 0, respondents: 1}]
    end

    test "actives sms -> ivr with no retries 1 respondent in 2nd attempt" do
      mode = ["sms", "ivr"]
      survey = insert(:survey, %{fallback_delay: "2h"})
      %{attempt: 2, mode: mode, retry_time: "", survey_id: survey.id}
        |> increase_stat(1)

      %{actives: actives} = survey |> Survey.retries_histogram(mode)

      assert actives == [%{hour: 2, respondents: 1}]
    end

    test "actives ivr -> sms with several retries and respondents" do
      mode = ["ivr", "sms"]
      survey = insert(:survey, %{ivr_retry_configuration: "2h", sms_retry_configuration: "3h", fallback_delay: "4h"})
      now = Timex.now()

      %{attempt: 1, mode: mode, retry_time: "", survey_id: survey.id}
        |> increase_stat(1)

      %{attempt: 2, mode: mode, retry_time: "", survey_id: survey.id}
        |> increase_stat(2)

      retry_time = now |> RetryStat.retry_time()

      %{attempt: 3, mode: mode, retry_time: retry_time, survey_id: survey.id}
        |> increase_stat(3)

      %{attempt: 4, mode: mode, retry_time: retry_time, survey_id: survey.id}
        |> increase_stat(4)

      retry_time = now |> Timex.shift(hours: 1) |> RetryStat.retry_time()

      %{attempt: 1, mode: mode, retry_time: retry_time, survey_id: survey.id}
        |> increase_stat(5)

      %{attempt: 2, mode: mode, retry_time: retry_time, survey_id: survey.id}
        |> increase_stat(6)

      %{attempt: 3, mode: mode, retry_time: retry_time, survey_id: survey.id}
        |> increase_stat(7)

      %{actives: actives} = survey |> Survey.retries_histogram(mode)

      assert actives == [
               %{hour: 0, respondents: 1},
               %{hour: 1, respondents: 5},
               %{hour: 2, respondents: 2},
               %{hour: 5, respondents: 6},
               %{hour: 6, respondents: 3},
               %{hour: 8, respondents: 7},
               %{hour: 9, respondents: 4}
             ]
    end
  end

  defp test_actives_no_retries_no_respondent(mode) do
    survey = insert(:survey)
    %{actives: actives} = survey
      |> Survey.retries_histogram([mode])

    assert actives == []
  end

  defp test_actives_1_retry_no_respondents(mode) do
    survey = insert(:survey, mode |> retry_configuration("2h"))
    %{actives: actives} = survey |> Survey.retries_histogram([mode])
    assert actives == []
  end

  defp test_actives_1_retry_1_respondent(mode, attempt, hour) do
    survey = insert(:survey, mode |> retry_configuration("2h"))
    %{attempt: attempt, mode: [mode], retry_time: active_retry_time(mode), survey_id: survey.id}
      |> increase_stat(1)

    %{actives: actives} = survey |> Survey.retries_histogram([mode])

    assert actives == [%{hour: hour, respondents: 1}]
  end

  defp test_actives_no_retries_1_respondent(mode) do
    survey = insert(:survey)
    %{attempt: 1, mode: [mode], retry_time: active_retry_time(mode), survey_id: survey.id}
      |> increase_stat(1)
    %{actives: actives} = survey
      |> Survey.retries_histogram([mode])
    assert actives == [%{hour: 0, respondents: 1}]
  end

  defp test_actives_1_retry_1_respondent_waiting(mode) do
    survey = insert(:survey, mode |> retry_configuration("2h"))
    retry_time = Timex.now() |> Timex.shift(hours: 1) |> RetryStat.retry_time()

    %{attempt: 1, mode: [mode], retry_time: retry_time, survey_id: survey.id}
      |> increase_stat(1)

      %{actives: actives} = survey |> Survey.retries_histogram([mode])

      assert actives == [%{hour: 1, respondents: 1}]
  end

  defp test_actives_2_retries_6_respondents(mode) do
    survey = insert(:survey, mode |> retry_configuration("2h 3h"))
    now = Timex.now()

    %{attempt: 1, mode: [mode], retry_time: active_retry_time(mode), survey_id: survey.id}
      |> increase_stat(3)

    %{attempt: 2, mode: [mode], retry_time: active_retry_time(mode), survey_id: survey.id}
      |> increase_stat(1)

    retry_time = now |> Timex.shift(hours: 2) |> RetryStat.retry_time()
    %{attempt: 2, mode: [mode], retry_time: retry_time, survey_id: survey.id}
      |> increase_stat(2)

    %{actives: actives} = survey |> Survey.retries_histogram([mode])

    assert actives == [
             %{hour: 0, respondents: 3},
             %{hour: 2, respondents: 1},
             %{hour: 3, respondents: 2}
           ]
  end

  defp retry_configuration("sms", retry_configuration), do: %{sms_retry_configuration: retry_configuration}
  defp retry_configuration("ivr", retry_configuration), do: %{ivr_retry_configuration: retry_configuration}
  defp retry_configuration("mobileweb", retry_configuration), do: %{mobileweb_retry_configuration: retry_configuration}

  defp test_actives_2_overdue(mode) do
    survey = insert(:survey, mode |> retry_configuration("2h"))
    now = Timex.now()

    retry_time = now |> Timex.shift(hours: -2) |> RetryStat.retry_time()
    %{attempt: 2, mode: [mode], retry_time: retry_time, survey_id: survey.id}
      |> increase_stat(1)

    retry_time = now |> Timex.shift(hours: -1) |> RetryStat.retry_time()
    %{attempt: 2, mode: [mode], retry_time: retry_time, survey_id: survey.id}
      |> increase_stat(1)

    %{attempt: 2, mode: [mode], retry_time: active_retry_time(mode), survey_id: survey.id}
      |> increase_stat(1)

    %{actives: actives} = survey |> Survey.retries_histogram([mode])

    assert actives == [%{hour: 2, respondents: 3}]
  end

  defp active_retry_time("ivr"), do: ""
  defp active_retry_time(_), do: Timex.now() |> RetryStat.retry_time()

  defp increase_stat(filter, n) when n <= 1 do
    {:ok, _} = RetryStat.add!(filter)
  end

  defp increase_stat(filter, n) do
    {:ok, _} = RetryStat.add!(filter)
    increase_stat(filter, n - 1)
  end
end
