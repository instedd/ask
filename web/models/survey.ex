defmodule Ask.Survey do
  use Ask.Web, :model

  alias __MODULE__

  @max_int 2147483647

  schema "surveys" do
    field :name, :string
    field :mode, Ask.Ecto.Type.JSON
    field :state, :string, default: "not_ready" # not_ready, ready, pending, running, completed, cancelled
    field :cutoff, :integer
    field :count_partial_results, :boolean, default: false
    field :respondents_count, :integer, virtual: true
    field :schedule_day_of_week, Ask.DayOfWeek, default: Ask.DayOfWeek.never
    field :schedule_start_time, Ecto.Time
    field :schedule_end_time, Ecto.Time
    field :timezone, :string
    field :started_at, Timex.Ecto.DateTime
    field :sms_retry_configuration, :string
    field :ivr_retry_configuration, :string
    field :mobileweb_retry_configuration, :string
    field :fallback_delay, :string
    field :quota_vars, Ask.Ecto.Type.JSON, default: []
    field :quotas, Ask.Ecto.Type.JSON, virtual: true
    field :comparisons, Ask.Ecto.Type.JSON, default: []

    has_many :respondent_groups, Ask.RespondentGroup
    has_many :respondents, Ask.Respondent
    has_many :quota_buckets, Ask.QuotaBucket, on_replace: :delete
    many_to_many :questionnaires, Ask.Questionnaire, join_through: Ask.SurveyQuestionnaire, on_replace: :delete

    belongs_to :project, Ask.Project

    timestamps()
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:name, :project_id, :mode, :state, :cutoff, :respondents_count, :schedule_day_of_week, :schedule_start_time, :schedule_end_time, :timezone, :sms_retry_configuration, :ivr_retry_configuration, :mobileweb_retry_configuration, :fallback_delay, :started_at, :quotas, :quota_vars, :comparisons, :count_partial_results])
    |> validate_required([:project_id, :state, :schedule_start_time, :schedule_end_time, :timezone])
    |> foreign_key_constraint(:project_id)
    |> validate_from_less_than_to
    |> validate_number(:cutoff, greater_than: 0, less_than: @max_int)
    |> translate_quotas
  end

  defp translate_quotas(changeset) do
    if quotas = get_field(changeset, :quotas) do
      delete_change(changeset, :quotas)
      |> change(quota_vars: quotas["vars"])
      |> put_assoc(:quota_buckets, Ask.QuotaBucket.build_changeset(changeset.data, quotas["buckets"]))
      |> cast_assoc(:quota_buckets)
    else
      changeset
    end
  end

  def update_state(changeset) do
    ready =
      mode_ready?(changeset) &&
      schedule_ready?(changeset) &&
      retry_attempts_ready?(changeset) &&
      fallback_delay_ready?(changeset) &&
      comparisons_ready?(changeset) &&
      questionnaires_ready?(changeset) &&
      respondent_groups_ready?(changeset) &&
      mode_and_questionnaires_ready?(changeset)

    state = get_field(changeset, :state)

    cond do
      state == "not_ready" && ready ->
        change(changeset, state: "ready")
      state == "ready" && !ready ->
        change(changeset, state: "not_ready")
      true ->
        changeset
    end
  end

  def validate_from_less_than_to(changeset) do
    from = get_field(changeset, :schedule_start_time)
    to = get_field(changeset, :schedule_end_time)

    cond do
      from && to && from >= to ->
        add_error(changeset, :from, "has to be less than the To")
      true ->
        changeset
    end
  end

  defp questionnaires_ready?(changeset) do
    questionnaires = get_field(changeset, :questionnaires)
    length(questionnaires) > 0 && Enum.all?(questionnaires, &(&1.valid))
  end

  defp schedule_ready?(changeset) do
    schedule = get_field(changeset, :schedule_day_of_week)

    [ _ | values ] = Map.values(schedule)
    Enum.reduce(values, fn (x, acc) -> acc || x end)
  end

  defp mode_ready?(changeset) do
    mode = get_field(changeset, :mode)
    mode && length(mode) > 0
  end

  defp mode_and_questionnaires_ready?(changeset) do
    mode = get_field(changeset, :mode)
    questionnaires = get_field(changeset, :questionnaires)

    # Check that all survey modes are present in the associated questionnaires
    mode |> Enum.all?(fn modes ->
      modes |> Enum.all?(fn mode ->
        questionnaires |> Enum.all?(fn q ->
          q.modes |> Enum.member?(mode)
        end)
      end)
    end)
  end

  def comparisons_ready?(changeset) do
    comparisons = get_field(changeset, :comparisons)
    if comparisons && length(comparisons) > 0 do
      sum = comparisons
      |> Enum.map(&Map.get(&1, "ratio", 0))
      |> Enum.sum
      sum == 100
    else
      true
    end
  end

  defp respondent_groups_ready?(changeset) do
    mode = get_field(changeset, :mode)
    respondent_groups = get_field(changeset, :respondent_groups)
    respondent_groups &&
      length(respondent_groups) > 0 &&
      Enum.all?(respondent_groups, &respondent_group_ready?(&1, mode))
  end

  defp respondent_group_ready?(respondent_group, mode) do
    channels = respondent_group.respondent_group_channels
    Enum.all?(mode, fn(modes) ->
      Enum.all?(modes, fn(m) -> Enum.any?(channels, fn(c) -> m == c.mode end) end)
    end)
  end

  defp retry_attempts_ready?(changeset) do
    sms_retry_configuration = get_field(changeset, :sms_retry_configuration)
    ivr_retry_configuration = get_field(changeset, :ivr_retry_configuration)
    mobileweb_retry_configuration = get_field(changeset, :mobileweb_retry_configuration)
    valid_retry_configurations?(sms_retry_configuration) && valid_retry_configurations?(ivr_retry_configuration) && valid_retry_configurations?(mobileweb_retry_configuration)
  end

  defp fallback_delay_ready?(changeset) do
    fallback_delay = get_field(changeset, :fallback_delay)
    valid_retry_configuration?(fallback_delay)
  end

  defp valid_retry_configurations?(retry_configurations) do
    !retry_configurations || Enum.all?(String.split(retry_configurations), fn s -> valid_retry_configuration?(s) end)
  end

  defp valid_retry_configuration?(retry_configuration) do
    !retry_configuration || Regex.match?(~r/^\d+[mdh]$/, retry_configuration)
  end

  def retries_configuration(survey, mode) do
    retries = case mode do
      "sms" -> survey.sms_retry_configuration
      "ivr" -> survey.ivr_retry_configuration
      "mobileweb" -> survey.mobileweb_retry_configuration
      _ -> nil
    end

    parse_retries(retries)
  end

  def fallback_delay(survey) do
    if survey.fallback_delay do
      parse_retry_item(survey.fallback_delay |> String.trim, nil)
    else
      nil
    end
  end

  defp parse_retries(nil), do: []

  defp parse_retries(retries) do
    retries
    |> String.split
    |> Enum.map(&parse_retry_item(&1))
    |> Enum.reject(fn x -> x == 0 end)
  end

  defp parse_retry_item(value, on_error \\ 0) do
    case Integer.parse(value) do
      :error -> on_error
      {value, type} ->
        case type do
          "m" -> value
          "h" -> value * 60
          "d" -> value * 60 * 24
          _ -> on_error
        end
    end
  end

  def next_available_date_time(survey, date_time = %DateTime{}) do
    survey |>
    next_available_date_time(date_time |> Timex.to_erl |> Ecto.DateTime.from_erl)
  end

  def next_available_date_time(survey, date_time = %Ecto.DateTime{}) do
    {erl_date, erl_time} = date_time |> Ecto.DateTime.to_erl |> Timex.Timezone.convert(survey.timezone) |> Timex.to_erl
    adjusted_date_time = {erl_date, erl_time} |> Ecto.DateTime.from_erl

    # If this day is enabled in the survey
    if day_of_week_available?(survey, erl_date) do
      # Check if the time is inside the survey time range
      case compare_date_time(survey, adjusted_date_time) do
        :before ->
          # If it's before the time range, move it to the beginning of the range
          at_schedule_start_time(survey, erl_date)
        :inside ->
          # If it's inside there's nothing to do
          date_time
        :after ->
          # If it's after the time range, find the next day
          next_available_date_time_internal(survey, erl_date)
      end
    else
      # If the day is not enabled, find the next day
      next_available_date_time_internal(survey, erl_date)
    end
  end

  defp day_of_week_available?(survey, erl_date) do
    case :calendar.day_of_the_week(erl_date) do
      1 -> survey.schedule_day_of_week.mon
      2 -> survey.schedule_day_of_week.tue
      3 -> survey.schedule_day_of_week.wed
      4 -> survey.schedule_day_of_week.thu
      5 -> survey.schedule_day_of_week.fri
      6 -> survey.schedule_day_of_week.sat
      7 -> survey.schedule_day_of_week.sun
    end
  end

  defp compare_date_time(%Survey{schedule_start_time: start_time, schedule_end_time: end_time}, date_time) do
    time = Ecto.DateTime.to_time(date_time)
    case Ecto.Time.compare(time, start_time) do
      :lt -> :before
      :eq -> :inside
      :gt ->
        case Ecto.Time.compare(time, end_time) do
          :lt -> :inside
          :eq -> :inside
          :gt -> :after
        end
    end
  end

  defp at_schedule_start_time(survey, erl_date) do
    erl_time = survey.schedule_start_time |> Ecto.Time.to_erl
    Timex.Timezone.resolve(survey.timezone, {erl_date, erl_time})
    |> Timex.Timezone.convert("UTC")
    |> Timex.to_erl
    |> Ecto.DateTime.from_erl
  end

  defp next_available_date_time_internal(survey, erl_date) do
    erl_date = next_available_date(survey, erl_date)
    at_schedule_start_time(survey, erl_date)
  end

  defp next_available_date(survey, erl_date) do
    erl_date = Timex.shift(erl_date, days: 1)
    if day_of_week_available?(survey, erl_date) do
      erl_date
    else
      next_available_date(survey, erl_date)
    end
  end
end
