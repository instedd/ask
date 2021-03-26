defmodule Ask.Schedule do
  @moduledoc """
  A custom type to map schedules to the database

  This type contains an Ask.DayOfWeek, start and end time for each day, and
  a list of blocked days such as holidays
  """

  @behaviour Ecto.Type

  alias __MODULE__
  alias Ask.DayOfWeek

  defstruct [:day_of_week, :start_time, :end_time, :blocked_days, :timezone, :start_date, :end_date]

  def type, do: :text

  def cast(%Schedule{} = schedule) do
    {:ok, schedule}
  end
  def cast(%{start_time: start_time} = schedule) when is_binary(start_time) do
    cast(%{schedule | start_time: Time.from_iso8601!(start_time)})
  end
  def cast(%{end_time: end_time} = schedule) when is_binary(end_time) do
    cast(%{schedule | end_time: Time.from_iso8601!(end_time)})
  end
  def cast(%{start_date: start_date} = schedule) when is_binary(start_date) do
    cast(%{schedule | start_date: Date.from_iso8601!(start_date)})
  end
  def cast(%{end_date: end_date} = schedule) when is_binary(end_date) do
    cast(%{schedule | end_date: Date.from_iso8601!(end_date)})
  end
  def cast(%{day_of_week: day_of_week, start_time: start_time, end_time: end_time, blocked_days: blocked_days, timezone: timezone, start_date: start_date, end_date: end_date}) do
    case DayOfWeek.cast(day_of_week) do
      :error -> :error
      {:ok, dow} ->
        {:ok, %Schedule{day_of_week: dow, start_time: start_time, end_time: end_time, blocked_days: cast_blocked_days(blocked_days), timezone: timezone, start_date: start_date, end_date: end_date}}
    end
  end
  def cast(%{} = map) do
    cast(%{
      day_of_week: map["day_of_week"],
      start_time: map["start_time"],
      end_time: map["end_time"],
      blocked_days: map["blocked_days"],
      timezone: map["timezone"],
      start_date: map["start_date"],
      end_date: map["end_date"]
    })
  end
  def cast(string) when is_binary(string), do: load(string)
  def cast(nil), do: {:ok, default()}
  def cast(_), do: :error

  defp cast_blocked_days([blocked_day | blocked_days]) when is_binary(blocked_day) do
    [Date.from_iso8601!(blocked_day) | cast_blocked_days(blocked_days)]
  end
  defp cast_blocked_days([blocked_day | blocked_days]) do
    [blocked_day | cast_blocked_days(blocked_days)]
  end
  defp cast_blocked_days(_), do: []

  def load(string) when is_binary(string), do: cast(Poison.decode!(string))
  def load(nil), do: {:ok, always()}
  def load(_), do: :error

  def load!(schedule) do
    case load(schedule) do
      {:ok, schedule} -> schedule
      :error -> raise "Schedule load error #{inspect(schedule)}"
    end
  end

  def dump(%Schedule{day_of_week: day_of_week}=schedule) do
    {:ok, day_of_week}= DayOfWeek.dump(day_of_week)
    schedule = %{schedule |
      day_of_week: day_of_week,
      blocked_days: schedule.blocked_days || []
    }
    Poison.encode(schedule)
  end
  def dump(_), do: :error

  def dump!(schedule) do
    case dump(schedule) do
      {:ok, schedule} -> schedule
      :error -> raise "Schedule dump error #{inspect(schedule)}"
    end
  end

  def validate(schedule) do
    if schedule.start_time && schedule.end_time && schedule.start_time >= schedule.end_time do
      :error
    else
      :ok
    end
  end

  def intersect?(%Schedule{day_of_week: days, start_time: start_time, end_time: end_time, timezone: timezone, blocked_days: blocked_days, start_date: start_date}, %DateTime{} = date_time) do
    date_time = date_time
    |> Timex.to_datetime(timezone)

    time = DateTime.to_time(date_time)
    date = DateTime.to_date(date_time)

    DayOfWeek.intersect?(days, DayOfWeek.from(date_time))
      && !Enum.member?(blocked_days, date_time |> Timex.to_date)
      && Time.compare(start_time, time) != :gt
      && Time.compare(end_time, time) != :lt
      && (!start_date || Date.compare(start_date, date) != :gt)
  end

  def business_day(), do:
    %Schedule{
      day_of_week: %DayOfWeek{sun: false, mon: true, tue: true, wed: true, thu: true, fri: true, sat: false},
      start_time: ~T[09:00:00],
      end_time: ~T[18:00:00],
      blocked_days: [],
      timezone: default_timezone()
    }

  def default() do
    %Schedule{
      day_of_week: DayOfWeek.never(),
      start_time: ~T[09:00:00],
      end_time: ~T[18:00:00],
      blocked_days: [],
      timezone: default_timezone()
    }
  end

  def always() do
    %Schedule{
      day_of_week: DayOfWeek.every_day(),
      start_time: ~T[00:00:00],
      end_time: ~T[23:59:59],
      blocked_days: [],
      timezone: default_timezone()
    }
  end

  def default_timezone() do
    "Etc/UTC"
  end

  def next_available_date_time(%Schedule{} = schedule, %DateTime{} = date_time \\ DateTime.utc_now) do
    # TODO: Remove the necessity of converting this to erl dates
    date_time = date_time
    |> Timex.to_datetime(schedule.timezone)

    {erl_date, erl_time} = date_time |> Timex.to_erl

    {:ok, time} = erl_time
    |> Time.from_erl

    backward = false

    # If this day is enabled in the schedule
    date_time = if day_of_week_available?(schedule, erl_date) do
      # Check if the time is inside the schedule time range
      case compare_time(schedule, time) do
        :before ->
          # If it's before the time range, move it to the beginning of the range
          at_start_time(schedule, erl_date)
        :inside ->
          # If it's inside there's nothing to do
          date_time
        :after ->
          # If it's after the time range, find the next day
          next_available_date_time_internal(schedule, erl_date, backward)
      end
    else
      # If the day is not enabled, find the next day
      next_available_date_time_internal(schedule, erl_date, backward)
    end

    date_time
    |> Timex.Timezone.convert("Etc/UTC")
  end

  def last_window_ends_at(%{end_date: nil} = _schedule), do: nil

  def last_window_ends_at(%{end_date: end_date} = schedule) do
    end_date = end_date
    |> Date.add(1)
    |> Timex.to_datetime(schedule.timezone)

    {erl_date, erl_time} = end_date |> Timex.to_erl

    {:ok, time} = erl_time
    |> Time.from_erl

    backward = true

    # If this day is enabled in the schedule
    last_window_ends_at = if day_of_week_available?(schedule, erl_date) do
      # Check if the time is inside the schedule time range
      case compare_time(schedule, time) do
        :before ->
          # If it's before the time range, find the previous day
          next_available_date_time_internal(schedule, erl_date, backward)
        :inside ->
          # If it's inside there's nothing to do
            end_date
        :after ->
          # If it's afer the time range, move it to the end of the range
          at_end_time(schedule, erl_date)
      end
    else
      # If the day is not enabled, find the previous day
      next_available_date_time_internal(schedule, erl_date, backward)
    end

    last_window_ends_at
    |> Timex.Timezone.convert("Etc/UTC")
  end

  def at_end_time(%Schedule{end_time: end_time, timezone: timezone}, %DateTime{} = date_time) do
    {erlang_date, _} = date_time |> Timex.Timezone.convert(timezone) |> Timex.to_erl
    erlang_time = end_time |> Time.to_erl
    Timex.Timezone.resolve(timezone, {erlang_date, erlang_time})
  end

  def remove_start_date(schedule) do
    Map.put(schedule, :start_date, nil)
  end

  def remove_end_date(schedule) do
    Map.put(schedule, :end_date, nil)
  end

  defp compare_time(%Schedule{start_time: start_time, end_time: end_time}, time) do
    case Time.compare(time, start_time) do
      :lt -> :before
      :eq -> :inside
      :gt ->
        case Time.compare(time, end_time) do
          :lt -> :inside
          :eq -> :inside
          :gt -> :after
        end
    end
  end

  defp at_start_time(schedule, erl_date) do
    erl_time = schedule.start_time |> Time.to_erl
    Timex.Timezone.resolve(schedule.timezone, {erl_date, erl_time})
  end

  defp at_end_time_erl(schedule, erl_date) do
    erl_time = schedule.end_time |> Time.to_erl
    Timex.Timezone.resolve(schedule.timezone, {erl_date, erl_time})
  end

  defp next_available_date_time_internal(schedule, erl_date, backward) do
    erl_date = next_available_date(schedule, erl_date, backward)
    if backward, do: at_end_time_erl(schedule, erl_date), else: at_start_time(schedule, erl_date)
  end

  defp next_available_date(schedule, erl_date, backward) do
    shift_days = if backward, do: -1, else: 1
    erl_date = Timex.shift(erl_date, days: shift_days)
    if day_of_week_available?(schedule, erl_date) do
      erl_date
    else
      next_available_date(schedule, erl_date, backward)
    end
  end

  defp day_of_week_available?(%Schedule{day_of_week: day_of_week, blocked_days: blocked_days, start_date: start_date}, erl_date) do
    date = Date.from_erl!(erl_date)
    if day_of_week == DayOfWeek.never do
      # Just in case a schedule remains empty (can happen in a test)
      true
    else
      case :calendar.day_of_the_week(erl_date) do
        1 -> day_of_week.mon
        2 -> day_of_week.tue
        3 -> day_of_week.wed
        4 -> day_of_week.thu
        5 -> day_of_week.fri
        6 -> day_of_week.sat
        7 -> day_of_week.sun
      end && !Enum.member?(blocked_days, date)
      && (!start_date || Date.compare(start_date, date) != :gt)
    end
  end

  def any_day_selected?(%Schedule{day_of_week: day_of_week}) do
    DayOfWeek.any_day_selected?(day_of_week)
  end

  def adjust_date_to_timezone(%Schedule{} = schedule, date) do
    date
    |> Timex.Timezone.convert(schedule.timezone)
  end

  def timezone_offset_in_seconds(%Schedule{} = schedule) do
    schedule.timezone
    |> Timex.Timezone.get
    |> Timex.Timezone.total_offset
  end

  def timezone_offset(%Schedule{} = schedule) do
    offset = timezone_offset_in_seconds(schedule)
    hours = round(offset / 60 / 60)
    cond do
      hours == 0 -> "UTC"
      hours < 0 -> "GMT#{hours}"
      hours > 0 -> "GMT+#{hours}"
    end
  end
end
