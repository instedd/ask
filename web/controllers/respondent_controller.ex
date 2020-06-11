defmodule Ask.RespondentController do
  use Ask.Web, :api_controller
  require Ask.RespondentStats

  alias Ask.{
    ActivityLog,
    CompletedRespondents,
    Logger,
    Questionnaire,
    Respondent,
    RespondentDispositionHistory,
    Stats,
    Survey,
    SurveyLogEntry
  }

  def index(conn, %{"project_id" => project_id, "survey_id" => survey_id} = params) do
    limit = Map.get(params, "limit", "")
    page = Map.get(params, "page", "")
    sort_by = Map.get(params, "sort_by", "")
    sort_asc = Map.get(params, "sort_asc", "")

    respondents = conn
    |> load_project(project_id)
    |> assoc(:surveys)
    |> Repo.get!(survey_id)
    |> assoc(:respondents)
    |> preload(:responses)
    |> conditional_limit(limit)
    |> conditional_page(limit, page)
    |> sort_respondents(sort_by, sort_asc)
    |> Repo.all
    |> Enum.map(fn respondent ->
      respondent
      |> mask_phone_numbers
      |> effective_stats
    end)

    respondents_count = Ask.RespondentStats.respondent_count(survey_id: ^survey_id)
    render(conn, "index.json", respondents: respondents, respondents_count: respondents_count)
  end

  defp effective_stats(respondent) do
    effective_stats = case respondent.stats do
      %{attempts: %{"ivr" => _ivr_attempts}} = stats ->
        effective_attempts = Map.put(stats.attempts, "ivr", Ask.Stats.attempts(stats, :ivr))
        %{stats | attempts: effective_attempts}
      stats -> stats
    end

    %{respondent | stats: effective_stats}
  end

  defp sort_respondents(query, sort_by, sort_asc) do
    case {sort_by, sort_asc} do
      {"phoneNumber", "true"} ->
        query |> order_by([r], asc: r.hashed_number)
      {"phoneNumber", "false"} ->
        query |> order_by([r], desc: r.hashed_number)
      {"date", "true"} ->
        query |> order_by([r], asc: r.updated_at)
      {"date", "false"} ->
        query |> order_by([r], desc: r.updated_at)
      _ ->
        query
    end
  end

  def stats(conn, %{"project_id" => project_id, "survey_id" => survey_id}) do
    survey =
      conn
      |> load_project(project_id)
      |> assoc(:surveys)
      |> Repo.get!(survey_id)

    stats(conn, survey, survey.quota_vars)
  rescue
    e ->
      Logger.error(e, "Error occurred while processing respondent stats (survey_id: #{survey_id})")
      Sentry.capture_exception(e, [
        stacktrace: System.stacktrace(),
        extra: %{survey_id: survey_id}])

      render(conn, "stats.json", stats: nil)
  end

  defp stats(conn, survey, []) do
    questionnaires = (survey |> Repo.preload(:questionnaires)).questionnaires
    respondent_count = Ask.RespondentStats.respondent_count(survey_id: ^survey.id)

    cond do
      length(questionnaires) > 1 && length(survey.mode) > 1 ->
        stats(
          conn,
          survey,
          respondent_count,
          respondents_by_questionnaire_mode_and_disposition(survey),
          respondents_by_questionnaire_mode_and_completed_at(survey),
          reference(questionnaires, survey.mode),
          [],
          "stats.json"
        )

      length(survey.mode) > 1 ->
        stats(
          conn,
          survey,
          respondent_count,
          respondents_by_mode_and_disposition(survey),
          respondents_by_mode_and_completed_at(survey),
          reference(questionnaires, survey.mode),
          [],
          "stats.json"
        )

      true ->
        stats(
          conn,
          survey,
          respondent_count,
          respondents_by_questionnaire_and_disposition(survey),
          respondents_by_questionnaire_and_completed_at(survey),
          reference(questionnaires, survey.mode),
          [],
          "stats.json"
        )
    end
  end

  defp stats(conn, survey, _) do
    buckets = (survey |> Repo.preload(:quota_buckets)).quota_buckets
    empty_bucket_ids = buckets |> Enum.filter(fn(bucket) -> bucket.quota in [0, nil] end) |> Enum.map(&(&1.id))
    buckets = buckets |> Enum.reject(fn(bucket) -> bucket.quota in [0, nil] end)
    respondent_count = Ask.RespondentStats.respondent_count(survey_id: ^survey.id)
    stats(
      conn,
      survey,
      respondent_count,
      respondents_by_bucket_and_disposition(survey, empty_bucket_ids),
      respondents_by_quota_bucket_and_completed_at(survey, empty_bucket_ids),
      buckets,
      buckets,
      "quotas_stats.json"
    )
  end

  defp stats(conn, survey, total_respondents, respondents_by_disposition, respondents_by_completed_at, references, buckets, layout) do
    target = target(survey, buckets, total_respondents)

    total_respondents_by_disposition =
      Ask.RespondentStats.respondent_count(survey_id: ^survey.id, by: :disposition)

    # Completion percentage
    attempted_respondents = total_respondents_by_disposition
      |> Enum.filter(fn {d, _} -> d not in ["queued", "registered"] end)
      |> Enum.map(fn {_, c} -> c end)
      |> Enum.sum

    dispositions_for_completion = Respondent.completed_dispositions(survey.count_partial_results)

    completed_or_partial = total_respondents_by_disposition
      |> Enum.filter(fn {d, _} -> d in dispositions_for_completion end)
      |> Enum.map(fn {_, c} -> c end)
      |> Enum.sum

    grouped_respondents =
      respondents_by_completed_at
      |> Enum.reduce(%{}, fn {group_id, date, count}, acc ->
        {_, next_acc} =
          acc
          |> Map.get_and_update(group_id, fn counts_by_date ->
            {counts_by_date, (counts_by_date || []) ++ [{date, count}]}
          end)

        next_acc
      end)

    stats = %{
      id: survey.id,
      reference: references,
      respondents_by_disposition: respondent_counts(respondents_by_disposition, total_respondents),
      cumulative_percentages: cumulative_percentages(references, grouped_respondents, survey, target, buckets),
      completion_percentage: completed_or_partial / target * 100,
      total_respondents: total_respondents,
      target: target,
      attempted_respondents: attempted_respondents
    }

    render(conn, layout, stats: stats)
  end

  defp reference([questionnaire], [modes]) do
    [
      %{
        id: questionnaire.id,
        name: questionnaire.name,
        modes: modes
      }
    ]
  end

  defp reference([_], mode) do
    mode
    |> Enum.map(fn modes ->
      %{
        id: modes |> Enum.join(""),
        modes: modes
      }
    end)
  end

  defp reference(questionnaires, [_]) do
    questionnaires
    |> Enum.map(fn q ->
      %{id: q.id, name: q.name}
    end)
  end

  defp reference(questionnaires, mode) do
    questionnaires
    |> Enum.reduce([], fn questionnaire, reference ->
      mode
      |> Enum.reduce(reference, fn modes, reference ->
        reference ++
          [
            %{
              id: "#{questionnaire.id}#{modes |> Enum.join("")}",
              name: questionnaire.name,
              modes: modes
            }
          ]
      end)
    end)
  end

  defp target(survey, buckets, total_respondents) do
    total_quota =
      buckets
      |> Enum.reduce(0, fn bucket, total ->
        total + (bucket.quota || 0)
      end)

    cond do
      total_quota > 0 -> total_quota
      !is_nil(survey.cutoff) -> survey.cutoff
      true -> total_respondents
    end
  end

  defp respondent_counts(grouped_responents, total_respondents) do
    respondent_counts =
      grouped_responents
      |> Enum.reduce(%{}, fn {state, disposition, reference_id, count}, counts ->
        disposition = disposition || state

        default_for_disposition = %{disposition => %{by_reference: %{}, count: 0}}
        counts = default_for_disposition |> Map.merge(counts)

        default_for_quota_bucket = %{to_string(reference_id) => count}
        by_reference =
          default_for_quota_bucket
          |> Map.merge(counts[disposition][:by_reference], fn (_, count, current_count) ->
            count + current_count
          end)

        disposition_total_count = counts[disposition][:count] + count

        counts |> Map.put(disposition, %{by_reference: by_reference, count: disposition_total_count})
      end)
    dispositions = ["registered", "queued", "failed", "contacted", "unresponsive", "started", "ineligible", "rejected", "breakoff", "refused", "interim partial", "partial", "completed"]
    respondent_counts =
      dispositions
      |> Enum.reduce(respondent_counts, fn (disposition, respondent_counts) ->
          respondent_counts |> Map.put_new(disposition, %{
            by_reference: %{},
            count: 0
          })
        end)

    respondent_counts = add_disposition_percent(respondent_counts, total_respondents)

    groups = %{
      uncontacted: ["registered", "queued", "failed"],
      contacted: ["contacted", "unresponsive"],
      responsive: ["started", "ineligible", "rejected", "breakoff", "refused", "interim partial", "partial", "completed"]
    }

    groups
    |> Enum.map(fn {name, dispositions} ->
        {count, percent, detail} =
          dispositions
          |> Enum.reduce({0, 0, %{}}, fn disposition, {count_sum, percent_sum, detail} ->
              {respondent_counts[disposition][:count] + count_sum, respondent_counts[disposition][:percent] + percent_sum, Map.put(detail, disposition, respondent_counts[disposition])}
            end)
        {name, %{ count: count, percent: percent, detail: detail }}
      end)
    |> Enum.into(%{})
  end

  defp percent_provider(_group_id, [], target, []) do
    fn count ->
      count / target * 100
    end
  end

  defp percent_provider(group_id, [], _target, buckets) do
    bucket = buckets |> Enum.find(fn bucket -> bucket.id == group_id end)

    fn count ->
      count / bucket.quota * 100
    end
  end

  defp percent_provider(group_id, comparisons, target, []) do
    comparison =
      comparisons
      |> Enum.find(fn comparison ->
        group_id == "#{comparison["questionnaire_id"]}#{comparison["mode"] |> Enum.join("")}" ||
          group_id == comparison["questionnaire_id"] || group_id == comparison["mode"] |> Enum.join("")
      end)

    fn count ->
      count / (comparison["ratio"] * target / 100) * 100
    end
  end

  defp cumulative_percentages(_, _, %{started_at: nil}, _, _), do: %{}

  defp cumulative_percentages(references, grouped_respondents, %{started_at: started_at, comparisons: comparisons, state: state}, target, buckets) do
    grouped_respondents
    |> Enum.into(Enum.map(references, fn reference -> {reference.id, []} end) |> Enum.into(%{}))
    |> Enum.map(fn {group_id, percents_by_date} ->
      # To make sure the series starts at the same time that the survey
      percents_by_date = [{started_at |> DateTime.to_date(), 0}] ++ percents_by_date

      percents_by_date = if state == "running" do
        percents_by_date ++ [{DateTime.utc_now() |> DateTime.to_date(), 0}]
      else
        percents_by_date
      end

      {group_id,
       cumulative_percents_for_group(
         percents_by_date,
         percent_provider(group_id, comparisons, target, buckets)
       )}
    end)
    |> Enum.into(%{})
  end

  defp cumulative_percents_for_group(
         percents_by_date,
         percent_provider,
         cumulative_percent \\ 0,
         result \\ []
       )

  defp cumulative_percents_for_group(_percents_by_date, _percent_provider, 100.0, result) do
    result
  end

  defp cumulative_percents_for_group(
         [{date, count}],
         percent_provider,
         cumulative_percent,
         result
       ) do
    result ++ [{date, cumulative_percent |> add_percent(count, percent_provider)}]
  end

  defp cumulative_percents_for_group(
         [{first_date, first_count}, {second_date, second_count} | rest_percents_by_date],
         percent_provider,
         cumulative_percent,
         result
       ) do
    case Date.diff(second_date, first_date) do
      0 ->
        # We already had results for that date and we duplicated the dot
        cumulative_percents_for_group(
          [{first_date, max(first_count, second_count)} | rest_percents_by_date],
          percent_provider,
          cumulative_percent,
          result
        )

      1 ->
        cumulative_percent = cumulative_percent |> add_percent(first_count, percent_provider)

        cumulative_percents_for_group(
          [{second_date, second_count} | rest_percents_by_date],
          percent_provider,
          cumulative_percent,
          result ++ [{first_date, cumulative_percent}]
        )

      _ ->
        cumulative_percent = cumulative_percent |> add_percent(first_count, percent_provider)

        if second_count > 0 do
          cumulative_percents_for_group(
            [
              {second_date |> Timex.shift(days: -1), 0},
              {second_date, second_count} | rest_percents_by_date
            ],
            percent_provider,
            cumulative_percent,
            result ++ [{first_date, cumulative_percent}]
          )
        else
          # We injected today's date with no aditional results
          # there's no need for an additional point to mark the horizontal line
          cumulative_percents_for_group(
            [
              {second_date, second_count} | rest_percents_by_date
            ],
            percent_provider,
            cumulative_percent,
            result ++ [{first_date, cumulative_percent}]
          )
        end
    end
  end

  defp add_percent(cumulative_percent, count, percent_provider) do
    (cumulative_percent + percent_provider.(count))
    |> min(100.0)
  end

  defp respondents_by_questionnaire_and_disposition(survey) do
    Ask.RespondentStats.respondent_count(survey_id: ^survey.id, by: [:state, :disposition, :questionnaire_id])
  end

  defp respondents_by_questionnaire_mode_and_disposition(survey) do
    Ask.RespondentStats.respondent_count(survey_id: ^survey.id, by: [:state, :disposition, :questionnaire_id, :mode])
    |> Enum.map(fn({state, disposition, questionnaire_id, mode, count}) ->
      reference_id = if mode && questionnaire_id do
        "#{questionnaire_id}#{mode |> Poison.decode! |> Enum.join("")}"
      else
        nil
      end

      {state, disposition, reference_id, count}
    end)
  end

  defp respondents_by_mode_and_disposition(survey) do
    Ask.RespondentStats.respondent_count(survey_id: ^survey.id, by: [:state, :disposition, :mode])
  end

  defp respondents_by_bucket_and_disposition(survey, bucket_ids) do
    Ask.RespondentStats.respondent_count(survey_id: ^survey.id, quota_bucket_id: not_in_list(^bucket_ids), by: [:state, :disposition, :quota_bucket_id])
  end

  defp respondents_by_questionnaire_and_completed_at(survey) do
    Repo.all(
      from r in CompletedRespondents,
      where: r.survey_id == ^survey.id,
      group_by: [r.questionnaire_id, r.date],
      order_by: r.date,
      select: {r.questionnaire_id, r.date, fragment("CAST(? AS UNSIGNED)", sum(r.count))})
  end

  defp respondents_by_questionnaire_mode_and_completed_at(survey) do
    Repo.all(
      from r in CompletedRespondents,
      where: r.survey_id == ^survey.id and r.questionnaire_id != 0 and r.mode != "",
      group_by: [r.questionnaire_id, r.mode, r.date],
      order_by: r.date,
      select: {r.questionnaire_id, r.mode, r.date, fragment("CAST(? AS UNSIGNED)", sum(r.count))})
    |> Enum.map(fn({questionnaire_id, mode, completed_at, count}) ->
      {"#{questionnaire_id}#{mode |> Poison.decode! |> Enum.join("")}", completed_at, count}
    end)
  end

  defp respondents_by_mode_and_completed_at(survey) do
    Repo.all(
      from r in CompletedRespondents,
      where: r.survey_id == ^survey.id,
      group_by: [r.mode, r.date],
      order_by: r.date,
      select: {r.mode, r.date, fragment("CAST(? AS UNSIGNED)", sum(r.count))})
    |> Enum.map(fn({mode, completed_at, count}) -> {mode |> Poison.decode! |> Enum.join(""), completed_at, count} end)
  end

  defp respondents_by_quota_bucket_and_completed_at(survey, bucket_ids) do
    Repo.all(
      from r in CompletedRespondents,
      where: r.survey_id == ^survey.id and r.quota_bucket_id not in ^bucket_ids,
      group_by: [r.quota_bucket_id, r.date],
      order_by: r.date,
      select: {r.quota_bucket_id, r.date, fragment("CAST(? AS UNSIGNED)", sum(r.count))})
  end

  defp add_disposition_percent(respondents_count_by_disposition_and_questionnaire, total_respondents) do
    respondents_count_by_disposition_and_questionnaire
    |> Enum.map(fn {disposition, counts} ->
        percent_of_disposition =
          case total_respondents do
            0 -> 0
            _ -> respondents_count_by_disposition_and_questionnaire[disposition][:count] / (total_respondents / 100)
          end
        counts_with_percent = counts |> Map.put(:percent, percent_of_disposition)
        {disposition, counts_with_percent}
      end)
    |> Enum.into(%{})
  end

  def sanitize_variable_name(s), do: s |> String.trim() |> String.replace(" ", "_")

  def results(conn, %{"project_id" => project_id, "survey_id" => survey_id} = params) do
    project = conn
    |> load_project(project_id)

    # Check that the survey is in the project
    survey = project
    |> assoc(:surveys)
    |> Repo.get!(survey_id)

    tz_offset = Survey.timezone_offset(survey)

    questionnaires = (survey |> Repo.preload(:questionnaires)).questionnaires
    has_comparisons = length(survey.comparisons) > 0

    # We first need to get all unique field names in all questionnaires
    all_fields = questionnaires
    |> Enum.flat_map(&Questionnaire.variables/1)
    |> Enum.map(fn s -> s |> sanitize_variable_name end)
    |> Enum.uniq
    |> Enum.reject(fn s -> String.length(s) == 0 end)

    dynamic = true

    dynamic =
      if params["since"] do
        dynamic([r1, r2], r2.updated_at > ^params["since"] and ^dynamic)
      else
        dynamic
      end

    dynamic =
      if params["disposition"] do
        dynamic([r1, r2], r2.disposition == ^params["disposition"] and ^dynamic)
      else
        dynamic
      end

    dynamic =
      if params["final"] do
        dynamic([r1, r2], r2.state == "completed" and ^dynamic)
      else
        dynamic
      end

    respondents = Stream.resource(
      fn -> 0 end,
      fn last_seen_id ->
        results = (
          from r1 in Respondent,
          join: r2 in Respondent, on: r1.id == r2.id,
          where: r2.survey_id == ^survey.id and r2.id > ^last_seen_id,
          where: ^dynamic,
          order_by: r2.id,
          limit: 1000,
          preload: [:responses, :respondent_group],
          select: r1
        ) |> Repo.all;

        case List.last(results) do
          %{id: last_id} -> {results, last_id}
          nil -> {:halt, last_seen_id}
        end
      end,
      fn _ -> [] end)


    render_results(conn, get_format(conn), project, survey, tz_offset, questionnaires, has_comparisons, all_fields, respondents)
  end

  defp render_results(conn, "json", _project, survey, _tz_offset, questionnaires, has_comparisons, _all_fields, respondents) do
    respondents_count = Ask.RespondentStats.respondent_count(survey_id: ^survey.id)
    respondents = if has_comparisons do
      respondents
      |> Stream.map(fn respondent ->
        experiment_name = if respondent.questionnaire_id && respondent.mode do
          questionnaire = questionnaires |> Enum.find(fn q -> q.id == respondent.questionnaire_id end)
          if questionnaire do
            experiment_name(questionnaire, respondent.mode)
          else
            "-"
          end
        else
          "-"
        end
        %{respondent | experiment_name: experiment_name}
      end)
    else
      respondents
    end

    {:ok, conn} = Repo.transaction(fn() ->
      render(conn, "index.json", respondents: respondents, respondents_count: respondents_count)
    end)
    conn
  end

  defp render_results(conn, "csv", project, survey, tz_offset, questionnaires, has_comparisons, all_fields, respondents) do
    stats = survey.mode |> Enum.flat_map(fn(modes) ->
      modes |> Enum.flat_map(fn(mode) ->
        case mode do
          "sms" -> [:total_sent_sms, :total_received_sms, :sms_attempts]
          "mobileweb" -> [:total_sent_sms, :total_received_sms, :mobileweb_attempts]
          "ivr" -> [:total_call_time, :ivr_attempts]
          _ -> []
        end
      end)
    end) |> Enum.uniq

    # Now traverse each respondent and create a row for it
    csv_rows = respondents
    |> Stream.map(fn respondent ->
        row = [respondent.hashed_number]
        responses = respondent.responses

        row = row ++ [Respondent.show_disposition(respondent.disposition)]

        date = case responses do
          [] -> nil
          _ -> responses
               |> Enum.map(fn r -> r.updated_at end)
               |> Enum.max
               |> Survey.adjust_timezone(survey)
        end

        row = if date do
          row ++ [date |> Timex.format!("%b %e, %Y %H:%M #{tz_offset}", :strftime)]
        else
          row ++ ["-"]
        end

        modes = (respondent.effective_modes || [])
        |> Enum.map(fn mode -> mode_label([mode]) end)
        |> Enum.join(", ")

        row = row ++ [modes]

        row = row ++ [respondent.user_stopped]

        row = row ++ Enum.map(stats, fn stat ->
          respondent |> respondent_stat(stat)
        end)

        row = row ++ [Respondent.show_section_order(respondent, questionnaires)]

        respondent_group = respondent.respondent_group.name

        row = row ++ [respondent_group]

        # We traverse all fields and see if there's a response for this respondent
        row = all_fields |> Enum.reduce(row, fn field_name, acc ->
          response = responses
          |> Enum.filter(fn response -> response.field_name |> sanitize_variable_name == field_name end)
          case response do
            [resp] ->
              value = resp.value

              # For the 'language' variable we convert the code to the native name
              value = if resp.field_name == "language" do
                LanguageNames.for(value) || value
              else
                value
              end

              acc ++ [value]
            _ ->
              acc ++ [""]
          end
        end)

        questionnaire_id = respondent.questionnaire_id
        mode = respondent.mode

        row = if has_comparisons do
          variant = if questionnaire_id && mode do
            questionnaire = questionnaires |> Enum.find(fn q -> q.id == questionnaire_id end)
            if questionnaire do
              experiment_name(questionnaire, mode)
            else
              "-"
            end
          else
            "-"
          end
          row ++ [variant]
        else
          row
        end

        row
    end)

    # Add header to csv_rows
    header = ["respondent_id", "disposition", "date", "modes", "user_stopped"]
    header = header ++ Enum.map(stats, fn stat ->
      case stat do
        :total_sent_sms -> "total_sent_sms"
        :total_received_sms -> "total_received_sms"
        :total_call_time -> "total_call_time"
        :sms_attempts -> "sms_attempts"
        :ivr_attempts -> "ivr_attempts"
        :mobileweb_attempts -> "mobileweb_attempts"
      end
    end)
    header = header ++ ["section_order", "sample_file"]
    header = header ++ all_fields
    header = if has_comparisons do
      header ++ ["variant"]
    else
      header
    end

    rows = Stream.concat([[header], csv_rows])

    filename = csv_filename(survey, "respondents")
    ActivityLog.download(project, conn, survey, "survey_results") |> Repo.insert
    conn |> csv_stream(rows, filename)
  end

  defp respondent_stat(respondent, :sms_attempts), do: respondent.stats |> Stats.attempts(:sms)
  defp respondent_stat(respondent, :ivr_attempts), do: respondent.stats |> Stats.attempts(:ivr)
  defp respondent_stat(respondent, :mobileweb_attempts), do: respondent.stats |> Stats.attempts(:mobileweb)
  defp respondent_stat(respondent, key), do: apply(Stats, key, [respondent.stats])

  def disposition_history(conn, %{"project_id" => project_id, "survey_id" => survey_id}) do
    project = conn
    |> load_project(project_id)

    # Check that the survey is in the project
    survey = project
    |> assoc(:surveys)
    |> Repo.get!(survey_id)

    history = Stream.resource(
      fn -> 0 end,
      fn last_id ->
        results = (
          from h in RespondentDispositionHistory,
          where: h.survey_id == ^survey.id and h.id > ^last_id,
          order_by: h.id,
          limit: 1000
        ) |> Repo.all

        case List.last(results) do
          nil -> {:halt, last_id}
          last_entry -> {results, last_entry.id}
        end
      end,
      fn _ -> [] end
    )

    tz_offset = Survey.timezone_offset(survey)
    offset_seconds = Survey.timezone_offset_in_seconds(survey)

    csv_rows = history
    |> Stream.map(fn history ->
      date = Ask.TimeUtil.format(Ecto.DateTime.cast!(history.inserted_at), offset_seconds, tz_offset)
      [history.respondent_hashed_number, history.disposition, mode_label([history.mode]), date]
    end)

    header = ["Respondent ID", "Disposition", "Mode", "Timestamp"]
    rows = Stream.concat([[header], csv_rows])

    filename = csv_filename(survey, "respondents_disposition_history")
    ActivityLog.download(project, conn, survey, "disposition_history") |> Repo.insert
    conn |> csv_stream(rows, filename)
  end

  def incentives(conn, %{"project_id" => project_id, "survey_id" => survey_id}) do
    project = conn
    |> load_project_for_owner(project_id)

    # Check that the survey is in the project
    survey = project
    |> assoc(:surveys)
    |> Repo.get!(survey_id)

    csv_rows = (from r in Respondent,
      where: r.survey_id == ^survey.id and r.disposition == "completed" and not is_nil(r.questionnaire_id),
      order_by: r.id)
    |> preload(:questionnaire)
    |> Repo.stream
    |> Stream.map(fn r ->
      [r.phone_number, experiment_name(r.questionnaire, r.mode), csv_datetime(r.completed_at, survey)]
    end)

    header = ["Telephone number", "Questionnaire-Mode", "Completion date"]
    rows = Stream.concat([[header], csv_rows])

    filename = csv_filename(survey, "respondents_incentives")
    ActivityLog.download(project, conn, survey, "incentives") |> Repo.insert
    {:ok, conn} = Repo.transaction(fn -> conn |> csv_stream(rows, filename) end)
    conn
  end

  def interactions(conn, %{"project_id" => project_id, "survey_id" => survey_id}) do
    project = conn
    |> load_project_for_owner(project_id)

    # Check that the survey is in the project
    survey = project
    |> assoc(:surveys)
    |> Repo.get!(survey_id)

    log_entries = Stream.resource(
      fn -> {"", 0} end,
      fn {last_hash, last_id} ->
        results = (
          from e in SurveyLogEntry,
          where: e.survey_id == ^survey.id and (
            (e.respondent_hashed_number == ^last_hash and e.id > ^last_id) or
            (e.respondent_hashed_number > ^last_hash)
          ),
          order_by: [e.respondent_hashed_number, e.id],
          limit: 1000,
          preload: :channel
        ) |> Repo.all

        case List.last(results) do
          nil -> {:halt, {last_hash, last_id}}
          last_entry -> {results, {last_entry.respondent_hashed_number, last_entry.id}}
        end
      end,
      fn _ -> [] end
    )

    csv_rows =
      log_entries
      |> Stream.map(fn e ->
        channel_name =
          if e.channel do
            e.channel.name
          else
            ""
          end

        disposition = disposition_label(e.disposition)
        action_type = action_type_label(e.action_type)
        timestamp = csv_datetime(e.timestamp, survey)

        [Integer.to_string(e.id), e.respondent_hashed_number, interactions_mode_label(e.mode), channel_name, disposition, action_type, e.action_data, timestamp]
      end)

    header = ["ID", "Respondent ID", "Mode", "Channel", "Disposition", "Action Type", "Action Data", "Timestamp"]
    rows = Stream.concat([[header], csv_rows])

    filename = csv_filename(survey, "respondents_interactions")
    ActivityLog.download(project, conn, survey, "interactions") |> Repo.insert
    conn |> csv_stream(rows, filename)
  end

  defp mask_phone_numbers(respondent) do
    %{respondent | phone_number: Respondent.mask_phone_number(respondent.phone_number)}
  end

  defp experiment_name(quiz, mode) do
    "#{questionnaire_name(quiz)} - #{mode_label(mode)}"
  end

  defp questionnaire_name(quiz) do
    quiz.name || "Untitled questionnaire"
  end

  defp mode_label(mode) do
    case mode do
      ["sms"] -> "SMS"
      ["sms", "ivr"] -> "SMS with phone call fallback"
      ["sms", "mobileweb"] -> "SMS with Mobile Web fallback"
      ["ivr"] -> "Phone call"
      ["ivr", "sms"] -> "Phone call with SMS fallback"
      ["ivr", "mobileweb"] -> "Phone call with Mobile Web fallback"
      ["mobileweb"] -> "Mobile Web"
      ["mobileweb", "sms"] -> "Mobile Web with SMS fallback"
      ["mobileweb", "ivr"] -> "Mobile Web with phone call fallback"
      _ -> "Unknown mode"
    end
  end

  defp interactions_mode_label(mode) do
    case mode do
      "mobileweb" -> "Mobile Web"
      _ -> String.upcase(mode)
    end
  end

  defp action_type_label(action) do
    case action do
      nil -> nil
      "contact" -> "Contact attempt"
      _ -> String.capitalize(action)
    end
  end

  defp disposition_label(disposition) do
    case disposition do
      nil -> nil
      _ -> String.capitalize(disposition)
    end
  end

  defp csv_filename(survey, prefix) do
    name = survey.name || "survey_id_#{survey.id}"
    name = Regex.replace(~r/[^a-zA-Z0-9_]/, name, "_")
    prefix = "#{name}-#{prefix}"
    Timex.format!(Timex.now, "#{prefix}_%Y-%m-%d-%H-%M-%S.csv", :strftime)
  end

  defp csv_datetime(nil, _), do: ""

  defp csv_datetime(dt, %Survey{} = survey) do
    tz_offset = Survey.timezone_offset(survey)
    offset_seconds = Survey.timezone_offset_in_seconds(survey)

    Ask.TimeUtil.format(Ecto.DateTime.cast!(dt), offset_seconds, tz_offset)
  end
end
