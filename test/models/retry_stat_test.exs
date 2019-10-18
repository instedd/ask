defmodule Ask.RetryStatTest do
  use Ask.ModelCase

  alias Ask.RetryStat

  @valid_attrs %{attempt: 1, count: 2, survey_id: 3, mode: "sms", retry_time: "2019101612"}
  @invalid_attrs %{}

  test "changeset with valid attributes" do
    changeset = RetryStat.changeset(%RetryStat{}, @valid_attrs)
    assert changeset.valid?
  end

  test "changeset with invalid attributes" do
    changeset = RetryStat.changeset(%RetryStat{}, @invalid_attrs)
    refute changeset.valid?
  end

  test "inserts stat" do
    survey = insert(:survey)
    filter = %{attempt: 1, mode: "sms", retry_time: "2019101615", survey_id: survey.id}

    {:ok,
     %Ask.RetryStat{attempt: attempt, mode: mode, retry_time: retry_time, survey_id: survey_id}} =
      RetryStat.add!(filter)

    %{attempt: f_attempt, mode: f_mode, retry_time: f_retry_time} = filter

    assert attempt == f_attempt
    assert mode == f_mode
    assert retry_time == f_retry_time
    assert survey_id == survey.id

    assert 1 == RetryStat.count(filter)
  end

  test "increases stat" do
    survey = insert(:survey)
    filter = %{attempt: 1, mode: "sms", retry_time: "2019101615", survey_id: survey.id}

    {:ok, _} = RetryStat.add!(filter)
    {:ok, _} = RetryStat.add!(filter)

    assert 2 = RetryStat.count(filter)
  end

  test "increases specific stat" do
    survey = insert(:survey)
    survey1 = insert(:survey)

    filter1 = %{attempt: 1, mode: "sms", retry_time: "2019101615", survey_id: survey.id}
    filter2 = %{attempt: 2, mode: "sms", retry_time: "2019101615", survey_id: survey.id}
    filter3 = %{attempt: 3, mode: "sms", retry_time: "2019101615", survey_id: survey.id}
    filter4 = %{attempt: 1, mode: "ivr", retry_time: "2019101615", survey_id: survey.id}
    filter5 = %{attempt: 1, mode: "ivr", retry_time: "2019101616", survey_id: survey.id}
    filter6 = %{attempt: 1, mode: "ivr", retry_time: "2019101616", survey_id: survey1.id}

    increase_stat(filter1, 1)
    increase_stat(filter2, 2)
    increase_stat(filter3, 3)
    increase_stat(filter4, 4)
    increase_stat(filter5, 5)
    increase_stat(filter6, 6)

    assert 1 = RetryStat.count(filter1)
    assert 2 = RetryStat.count(filter2)
    assert 3 = RetryStat.count(filter3)
    assert 4 = RetryStat.count(filter4)
    assert 5 = RetryStat.count(filter5)
    assert 6 = RetryStat.count(filter6)
  end

  test "decreases stat" do
    survey = insert(:survey)
    filter = %{attempt: 1, mode: "sms", retry_time: "2019101615", survey_id: survey.id}

    {:ok, _} = RetryStat.add!(filter)
    {:ok, _} = RetryStat.add!(filter)
    {:ok, _} = RetryStat.subtract!(filter)

    assert 1 = RetryStat.count(filter)
  end

  test "decreases specific stat" do
    survey = insert(:survey)
    survey1 = insert(:survey)
    filter1 = %{attempt: 1, mode: "sms", retry_time: "2019101615", survey_id: survey.id}
    filter2 = %{attempt: 2, mode: "sms", retry_time: "2019101615", survey_id: survey.id}
    filter3 = %{attempt: 3, mode: "sms", retry_time: "2019101615", survey_id: survey.id}
    filter4 = %{attempt: 1, mode: "ivr", retry_time: "2019101615", survey_id: survey.id}
    filter5 = %{attempt: 1, mode: "ivr", retry_time: "2019101616", survey_id: survey.id}
    filter6 = %{attempt: 1, mode: "ivr", retry_time: "2019101616", survey_id: survey1.id}

    increase_stat(filter1, 2)
    {:ok, _} = RetryStat.subtract!(filter1)
    increase_stat(filter2, 3)
    {:ok, _} = RetryStat.subtract!(filter2)
    increase_stat(filter3, 4)
    {:ok, _} = RetryStat.subtract!(filter3)
    increase_stat(filter4, 5)
    {:ok, _} = RetryStat.subtract!(filter4)
    increase_stat(filter5, 6)
    {:ok, _} = RetryStat.subtract!(filter5)
    increase_stat(filter6, 7)
    {:ok, _} = RetryStat.subtract!(filter6)

    assert 1 = RetryStat.count(filter1)
    assert 2 = RetryStat.count(filter2)
    assert 3 = RetryStat.count(filter3)
    assert 4 = RetryStat.count(filter4)
    assert 5 = RetryStat.count(filter5)
    assert 6 = RetryStat.count(filter6)
  end

  test "doesn't decrease unexistent stat" do
    survey = insert(:survey)
    filter = %{attempt: 1, mode: "sms", retry_time: "2019101615", survey_id: survey.id}

    {:error, :not_found} = RetryStat.subtract!(filter)

    assert 0 = RetryStat.count(filter)
  end

  test "doesn't decrease stat when zero" do
    survey = insert(:survey)
    filter = %{attempt: 1, mode: "sms", retry_time: "2019101615", survey_id: survey.id}

    {:ok, _} = RetryStat.add!(filter)
    {:ok, _} = RetryStat.subtract!(filter)

    {:error, :zero_reached} = RetryStat.subtract!(filter)

    assert 0 = RetryStat.count(filter)
  end

  test "increases stat concurrently" do
    survey = insert(:survey)
    filter = %{attempt: 1, mode: "sms", retry_time: "2019101615", survey_id: survey.id}

    task1 =
      Task.async(fn ->
        increase_stat(filter, 100)
      end)

    task2 =
      Task.async(fn ->
        increase_stat(filter, 100)
      end)

    Task.await(task1)
    Task.await(task2)

    assert 200 = RetryStat.count(filter)
  end

  test "decreases stat concurrently" do
    survey = insert(:survey)
    filter = %{attempt: 1, mode: "sms", retry_time: "2019101615", survey_id: survey.id}

    increase_stat(filter, 200)

    task1 =
      Task.async(fn ->
        decrease_stat(filter, 50)
      end)

    task2 =
      Task.async(fn ->
        decrease_stat(filter, 50)
      end)

    Task.await(task1)
    Task.await(task2)

    assert 100 = RetryStat.count(filter)
  end

  defp increase_stat(filter, n) when n <= 1 do
    {:ok, _} = RetryStat.add!(filter)
  end

  defp increase_stat(filter, n) do
    {:ok, _} = RetryStat.add!(filter)
    increase_stat(filter, n - 1)
  end

  defp decrease_stat(filter, n) when n <= 1 do
    {:ok, _} = RetryStat.subtract!(filter)
  end

  defp decrease_stat(filter, n) do
    {:ok, _} = RetryStat.subtract!(filter)
    decrease_stat(filter, n - 1)
  end
end
