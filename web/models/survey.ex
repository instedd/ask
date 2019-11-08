defmodule Ask.Survey do
  use Ask.Web, :model

  alias __MODULE__
  require Ask.RespondentStats
  alias Ask.{
    Schedule,
    ShortLink,
    Repo,
    Respondent,
    RespondentGroup,
    Channel,
    RespondentGroupChannel,
    QuotaBucket,
    Questionnaire,
    SurveyQuestionnaire,
    Project,
    FloipEndpoint,
    Folder,
    RespondentStats,
    ConfigHelper,
    RetryStat
  }
  alias Ask.Runtime.{Broker, ChannelStatusServer}
  alias Ask.Ecto.Type.JSON

  @max_int 2147483647

  schema "surveys" do
    field :name, :string
    field :description, :string
    field :mode, JSON
    field :state, :string, default: "not_ready" # not_ready, ready, pending, running, terminated
    field :locked, :boolean, default: false
    field :exit_code, :integer
    field :exit_message, :string
    field :cutoff, :integer
    field :count_partial_results, :boolean, default: false
    field :schedule, Schedule, default: Schedule.default()
    field :started_at, Timex.Ecto.DateTime
    field :sms_retry_configuration, :string
    field :ivr_retry_configuration, :string
    field :mobileweb_retry_configuration, :string
    field :fallback_delay, :string
    field :quota_vars, JSON, default: []
    field :quotas, JSON, virtual: true
    field :comparisons, JSON, default: []
    field :simulation, :boolean, default: false
    field :links, :any, virtual: true
    field :floip_package_id, :string
    field :down_channels, JSON, virtual: true, default: []

    has_many :respondent_groups, RespondentGroup
    has_many :respondents, Respondent
    has_many :quota_buckets, QuotaBucket, on_replace: :delete
    many_to_many :questionnaires, Questionnaire, join_through: SurveyQuestionnaire, on_replace: :delete

    has_many :floip_endpoints, FloipEndpoint

    belongs_to :project, Project
    belongs_to :folder, Folder

    timestamps()
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:name, :description, :project_id, :folder_id, :mode, :state, :locked, :exit_code, :exit_message, :cutoff, :schedule, :sms_retry_configuration, :ivr_retry_configuration, :mobileweb_retry_configuration, :fallback_delay, :started_at, :quotas, :quota_vars, :comparisons, :count_partial_results, :simulation])
    |> set_floip_package_id
    |> validate_required([:project_id, :state, :schedule])
    |> foreign_key_constraint(:project_id)
    |> validate_from_less_than_to
    |> validate_number(:cutoff, greater_than_or_equal_to: 0, less_than: @max_int)
    |> translate_quotas
  end

  defp translate_quotas(changeset) do
    if quotas = get_field(changeset, :quotas) do
      delete_change(changeset, :quotas)
      |> change(quota_vars: quotas["vars"])
      |> put_assoc(:quota_buckets, QuotaBucket.build_changeset(changeset.data, quotas["buckets"]))
      |> cast_assoc(:quota_buckets)
    else
      changeset
    end
  end

  defp set_floip_package_id(changeset) do
    unless get_field(changeset, :floip_package_id) do
      change(changeset, floip_package_id: Ecto.UUID.generate)
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
      mode_and_questionnaires_ready?(changeset) &&
      cutoff_ready?(changeset)

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

  def editable?(%{state: "running"}), do: false
  def editable?(%{state: "terminated"}), do: false
  def editable?(_), do: true

  def validate_from_less_than_to(changeset) do
    case Schedule.validate(get_field(changeset, :schedule)) do
      :error ->
        add_error(changeset, :from, "has to be less than the To")
      :ok ->
        changeset
    end
  end

  def packages(survey) do
    if Survey.has_floip_package?(survey) do
      [survey.floip_package_id]
    else
      []
    end
  end

  defp questionnaires_ready?(changeset) do
    questionnaires = get_field(changeset, :questionnaires)
    length(questionnaires) > 0 && Enum.all?(questionnaires, &(&1.valid))
  end

  defp schedule_ready?(changeset) do
    get_field(changeset, :schedule)
    |> Schedule.any_day_selected?
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

  def cutoff_ready?(changeset) do
    quota_buckets = get_field(changeset, :quota_buckets)
    cutoff = get_field(changeset, :cutoff)

    if quota_buckets && length(quota_buckets) > 0 do
          sum = quota_buckets
          |> Enum.map(&Map.get(&1, :quota, 0))
          |> Enum.filter(& &1)
          |> Enum.sum
          sum > 0 && !exists_quota_nil?(quota_buckets)
    else
      if Map.has_key?(changeset.changes, :cutoff) do
        !is_cutoff_zero?(cutoff)
      else
        true
      end
    end
  end

  def is_cutoff_zero?(cutoff) do
    cutoff == 0
  end

  def exists_quota_nil?(quota_buckets) do
    quota_count = quota_buckets
                  |> Enum.map(&Map.get(&1, :quota))
                  |> Enum.count(&is_nil(&1))

    quota_count > 0
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

  def next_available_date_time(%Survey{} = survey, %DateTime{} = date_time) do
    Schedule.next_available_date_time(survey.schedule, date_time)
  end

  def config_rates() do
    %{
      :valid_respondent_rate => environment_variable_named(:initial_valid_respondent_rate) / 100,
      :eligibility_rate      => environment_variable_named(:initial_eligibility_rate) / 100,
      :response_rate         => environment_variable_named(:initial_response_rate) / 100
    }
  end

  def environment_variable_named(name), do: ConfigHelper.get_config(Broker, name, &String.to_integer/1)

  def launched?(survey) do
    survey.state in ["running", "terminated"]
  end

  def adjust_timezone(date_time, %Survey{} = survey) do
    Schedule.adjust_date_to_timezone(survey.schedule, date_time)
  end

  def timezone_offset(%Survey{} = survey) do
    Schedule.timezone_offset(survey.schedule)
  end

  def timezone_offset_in_seconds(%Survey{} = survey) do
    Schedule.timezone_offset_in_seconds(survey.schedule)
  end

  def completed?(survey) do
    survey.state == "terminated" && survey.exit_code == 0
  end

  def cancelled?(survey) do
    survey.state == "terminated" && survey.exit_code == 1
  end

  def has_floip_package?(survey) do
    survey.state == "running" || survey.state == "terminated"
  end

  def cancel_respondents(survey) do
    from(r in Respondent, where: (((r.state == "active") or (r.state == "stalled")) and (r.survey_id == ^survey.id)))
    |> Repo.update_all(set: [state: "cancelled", session: nil, timeout_at: nil])
  end

  def with_links(%Survey{} = survey, level \\ "owner") do
    %{survey | links: links(survey, level)}
  end

  def links(%Survey{} = survey, "owner") do
    links([
      link_name(survey, :results),
      link_name(survey, :incentives),
      link_name(survey, :disposition_history),
      link_name(survey, :interactions)
    ])
  end

  def links(%Survey{} = survey, _) do
    links([
      link_name(survey, :results),
      link_name(survey, :disposition_history)
    ])
  end

  def links(names) do
    ShortLink |> where([l], l.name in ^names) |> Repo.all
  end

  def link_name(%{id: id}, :results), do: "survey/#{id}/results"
  def link_name(%{id: id}, :incentives), do: "survey/#{id}/incentives"
  def link_name(%{id: id}, :disposition_history), do: "survey/#{id}/disposition_history"
  def link_name(%{id: id}, :interactions), do: "survey/#{id}/interactions"

  def running_channels() do
    query = from s in Survey,
      where: s.state == "running",
      join: group in RespondentGroup,
      on: s.id == group.survey_id,
      join: rgc in RespondentGroupChannel,
      on: group.id == rgc.respondent_group_id,
      join: c in Channel,
      on: rgc.channel_id == c.id,
      select: c

    query |> Repo.all
  end

  def survey_channels(s) do
    (s.respondent_groups |> Enum.reduce([], fn group, channels ->
      (group.respondent_group_channels |> Enum.map(&(&1.channel))) ++ channels
    end)) |> Enum.sort_by(&(&1.id))
  end

  def with_down_channels(%Survey{} = survey) do
    channels = survey |> survey_channels
    down_channels = channels
      |> Enum.map(&(&1.id |> ChannelStatusServer.get_channel_status))
      |> Enum.filter(&(&1 != :up && &1 != :unknown))

    %{survey | down_channels: down_channels}
  end

  def stats(survey) do
    respondents_by_state = survey |> respondents_by_state
    respondents_total = Enum.map(respondents_by_state, fn {_, v} -> v end) |> Enum.reduce(fn q, acc -> q + acc end)
    respondents_target = survey
      |> completed_respondents_needed_by
      |> respondents_target(respondents_total)
    initial_success_rate = initial_success_rate()
    successful_respondents = survey |> successful_respondents(respondents_by_state)
    current_success_rate = success_rate(successful_respondents, respondents_by_state["completed"], respondents_by_state["failed"], respondents_by_state["rejected"])
    completion_rate = completion_rate(successful_respondents, respondents_target)
    estimated_success_rate = estimated_success_rate(initial_success_rate, current_success_rate, completion_rate)
    completes = respondents_by_state["completed"]
    pending = respondents_target - completes
    multiplier = Float.ceil(1/estimated_success_rate, 0)
    needed = pending*multiplier
    selected_respondents = respondents_count(respondents_by_state)
    missing = max(needed - selected_respondents, 0)
    %{
      success_rate_data: %{
        success_rate: current_success_rate,
        completion_rate: completion_rate,
        initial_success_rate: initial_success_rate,
        estimated_success_rate: estimated_success_rate,
      },
      queue_size_data: %{
        completes: completes,
        pending: pending,
        multiplier: multiplier,
        needed: needed,
        missing: missing
      }
    }
  end

  def retries_histograms(%Survey{mode: mode} = survey),
    do:
      mode |> Enum.map(fn mode -> survey |> retries_histogram(mode) end)

  def retries_histogram(%Survey{} = survey, mode),
    do: %{
      flow: survey |> retries_histogram_flow(mode),
      actives: survey |> retries_histogram_actives(mode) |> clean_empty_slots()
    }

  defp retries_histogram_actives(%Survey{id: survey_id} = survey, mode) do
    survey
    |> retries_histogram_flow(mode)
    |> absolute_delay_flow()
    |> Stream.with_index()
    |> Enum.reduce([], fn {%{absolute_delay: absolute_delay, delay: delay}, idx}, acc ->
      acc ++ attempt_respondents(survey_id, mode, idx + 1, delay - 1, absolute_delay)
    end)
  end

  defp attempt_respondents(survey_id, mode, attempt, delay, absolute_delay) when delay > 0 do
    retry_time = Timex.now() |> Timex.shift(hours: delay) |> retry_time()

    count =
      %{attempt: attempt - 1, mode: mode, retry_time: retry_time, survey_id: survey_id}
      |> RetryStat.count()

    [%{hour: absolute_delay - delay, respondents: count}] ++
      attempt_respondents(survey_id, mode, attempt, delay - 1, absolute_delay)
  end

  defp attempt_respondents(survey_id, mode, attempt, _, absolute_delay) do
    retry_time = Timex.now() |> retry_time()

    count =
      %{attempt: attempt, mode: mode, retry_time: retry_time, survey_id: survey_id, overdue: true}
      |> RetryStat.count()

    [%{hour: absolute_delay, respondents: count}]
  end

  defp absolute_delay_flow(flow) do
    {flow, _} =
      flow
      |> Enum.map_reduce(0, fn %{type: type, delay: delay}, acc_delay ->
        {%{type: type, delay: delay, absolute_delay: delay + acc_delay}, delay + acc_delay}
      end)

    flow
  end

  defp clean_empty_slots(slots),
    do: slots |> Enum.filter(fn %{respondents: count} -> count > 0 end)

  defp retry_time(time), do: Timex.format!(time, "%Y%0m%0d%H", :strftime)

  defp retries_histogram_flow(%Survey{} = survey, mode_sequence),
    do:
      mode_sequence
      |> Stream.with_index()
      |> Enum.reduce([], fn {mode, idx}, acc -> acc ++ flow_retries(survey, mode, idx) end)

  defp flow_retries(survey, mode, 0) do
    flow_retries_with_fallback(survey, mode)
  end

  defp flow_retries(survey, mode, _) do
    fallback_delay = Kernel.round(fallback_delay(survey) / 60)
    flow_retries_with_fallback(survey, mode, fallback_delay)
  end

  defp flow_retries_with_fallback(survey, mode, fallback_delay \\ 0) do
    delay_hours =
      survey
      |> retries_configuration(mode)
      |> Enum.map(fn retry_minutes -> Kernel.round(retry_minutes / 60) end)

    [
      fallback_delay |> flow_retry(mode)
      | delay_hours |> Enum.map(fn retry_hour -> flow_retry(retry_hour, mode) end)
    ]
  end

  defp flow_retry(0, mode), do: %{delay: 0, type: mode}

  defp flow_retry(delay_hours, mode),
    do: %{delay: delay_hours, label: "#{delay_hours}h", type: mode}

  defp respondents_count(respondents_by_state) do
    filter_key_list = ["active", "pending", "stalled"]
    Map.take(respondents_by_state, filter_key_list)|> Enum.reduce(0, fn({_k, total}, acc) -> total + acc end)
  end

  defp respondents_target(:all, respondents_total), do: respondents_total
  defp respondents_target(completed_respondents_needed, _), do: completed_respondents_needed

  def success_rate(_, 0, 0, 0), do: 1.0
  def success_rate(successful_respondents, completed_respondents, failed_respondents, rejected_respondents) do
    successful_respondents / (completed_respondents + failed_respondents + rejected_respondents)
  end

  def completion_rate(_, nil), do: 0.0
  def completion_rate(_, 0), do: 0.0
  def completion_rate(completed, respondents_target), do: completed / respondents_target

  def initial_success_rate() do
    %{:valid_respondent_rate => initial_valid_respondent_rate,
    :eligibility_rate => initial_eligibility_rate,
    :response_rate => initial_response_rate } = config_rates()

    initial_valid_respondent_rate * initial_eligibility_rate * initial_response_rate
  end

  def estimated_success_rate(initial_success_rate, current_success_rate, completion_rate), do: (1 - completion_rate) * initial_success_rate + completion_rate * current_success_rate

  def completed_respondents_needed_by(survey) do
    survey_id = survey.id
    quota_target = Repo.one(from q in QuotaBucket,
                      where: q.survey_id == ^survey_id,
                      select: sum(q.quota))
    cutoff_target = survey.cutoff
    targets_compacted = [quota_target, cutoff_target] |> Enum.reject(&is_nil/1)

    if targets_compacted |> Enum.empty? do
      :all
    else
      res = targets_compacted
            |> Enum.max()
            |> Decimal.new()
            |> Decimal.to_integer()
      res
    end
  end

  def respondents_by_state(survey) do
    by_state_defaults = %{
      "active" => 0,
      "pending" => 0,
      "completed" => 0,
      "stalled" => 0,
      "rejected" => 0,
      "failed" => 0,
    }

    RespondentStats.respondent_count(survey_id: ^survey.id, by: :state)
      |> Enum.into(by_state_defaults)
  end

  def successful_respondents(survey, nil) do
    respondents_by_state = survey |> respondents_by_state
    survey |> successful_respondents(respondents_by_state)
  end

  def successful_respondents(survey, respondents_by_state) do
    quota_completed = Repo.one(
      from q in (survey |> assoc(:quota_buckets)),
      select: fragment("sum(least(count, quota))")
    )

    case quota_completed do
      nil -> respondents_by_state["completed"]
      value -> value |> Decimal.to_integer
    end
  end
end
