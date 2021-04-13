defmodule Ask.ScheduleTest do
  use Ask.ModelCase
  alias Ask.{Schedule, DayOfWeek}

  @default_schedule Schedule.default()

  test "always" do
    assert %Schedule{day_of_week: %DayOfWeek{sun: true, mon: true, tue: true, wed: true, thu: true, fri: true, sat: true}, start_time: ~T[00:00:00], end_time: ~T[23:59:59], blocked_days: [], timezone: "Etc/UTC"} == Schedule.always()
  end

  test "default" do
    assert %Schedule{day_of_week: %DayOfWeek{}, start_time: ~T[09:00:00], end_time: ~T[18:00:00], blocked_days: [], timezone: "Etc/UTC"} == Schedule.default()
  end

  describe "dump:" do
    test "should dump weekdays" do
      assert {:ok, "{\"timezone\":\"Etc/UTC\",\"start_time\":\"09:00:00\",\"start_date\":null,\"end_time\":\"18:00:00\",\"end_date\":null,\"day_of_week\":[\"mon\",\"tue\",\"wed\",\"thu\",\"fri\"],\"blocked_days\":[]}"} == Schedule.dump(%Schedule{day_of_week: %DayOfWeek{mon: true, tue: true, wed: true, thu: true, fri: true}, start_time: ~T[09:00:00], end_time: ~T[18:00:00], timezone: Schedule.default_timezone()})
    end

    test "should dump default" do
      assert {:ok, "{\"timezone\":\"Etc/UTC\",\"start_time\":\"09:00:00\",\"start_date\":null,\"end_time\":\"18:00:00\",\"end_date\":null,\"day_of_week\":[],\"blocked_days\":[]}"} == Schedule.dump(Schedule.default())
    end

    test "should dump always" do
      assert {:ok, "{\"timezone\":\"Etc/UTC\",\"start_time\":\"00:00:00\",\"start_date\":null,\"end_time\":\"23:59:59\",\"end_date\":null,\"day_of_week\":[\"sun\",\"mon\",\"tue\",\"wed\",\"thu\",\"fri\",\"sat\"],\"blocked_days\":[]}"} == Schedule.dump(Schedule.always())
    end

    test "should dump blocked_days" do
      assert {:ok, "{\"timezone\":\"Etc/UTC\",\"start_time\":\"09:00:00\",\"start_date\":null,\"end_time\":\"18:00:00\",\"end_date\":null,\"day_of_week\":[\"mon\",\"tue\",\"wed\",\"thu\",\"fri\"],\"blocked_days\":[\"2016-01-01\",\"2017-02-03\"]}"} == Schedule.dump(%Schedule{day_of_week: %DayOfWeek{mon: true, tue: true, wed: true, thu: true, fri: true}, start_time: ~T[09:00:00], end_time: ~T[18:00:00], timezone: Schedule.default_timezone(), blocked_days: [~D[2016-01-01], ~D[2017-02-03]]})
    end
  end

  describe "load:" do
    test "should load weekdays" do
      assert {:ok, %Schedule{day_of_week: %DayOfWeek{mon: true, tue: true, wed: true, thu: true, fri: true, sun: false, sat: false}, start_time: ~T[09:00:00], start_date: nil, end_time: ~T[18:00:00], end_date: nil, blocked_days: [], timezone: "America/Argentina/Buenos_Aires"}} == Schedule.load("{\"timezone\":\"America/Argentina/Buenos_Aires\",\"start_time\":\"09:00:00\",\"start_date\":null,\"end_time\":\"18:00:00\",\"end_date\":null,\"day_of_week\":[\"mon\",\"tue\",\"wed\",\"thu\",\"fri\"],\"blocked_days\":[]}")
    end

    test "should load blocked_days" do
      assert {:ok, %Schedule{day_of_week: %DayOfWeek{mon: true, tue: true, wed: true, thu: true, fri: true, sun: false, sat: false}, start_time: ~T[09:00:00], start_date: nil, end_time: ~T[18:00:00], end_date: nil, blocked_days: [~D[2016-01-01], ~D[2017-02-03]], timezone: "America/Argentina/Buenos_Aires"}} == Schedule.load("{\"timezone\":\"America/Argentina/Buenos_Aires\",\"start_time\":\"09:00:00\",\"start_date\":null,\"end_time\":\"18:00:00\",\"end_date\":null,\"day_of_week\":[\"mon\",\"tue\",\"wed\",\"thu\",\"fri\"],\"blocked_days\":[\"2016-01-01\",\"2017-02-03\"]}")
    end

    test "should load without start_date for backward compatibility" do
      assert {:ok, %Schedule{day_of_week: %DayOfWeek{mon: true, tue: true, wed: true, thu: true, fri: true, sun: false, sat: false}, start_time: ~T[09:00:00], start_date: nil, end_time: ~T[18:00:00], end_date: nil, blocked_days: [], timezone: "America/Argentina/Buenos_Aires"}} == Schedule.load("{\"timezone\":\"America/Argentina/Buenos_Aires\",\"start_time\":\"09:00:00\",\"end_time\":\"18:00:00\",\"end_date\":null,\"day_of_week\":[\"mon\",\"tue\",\"wed\",\"thu\",\"fri\"],\"blocked_days\":[]}")
    end

    test "should load start_date" do
      assert {:ok, %Schedule{day_of_week: %DayOfWeek{mon: true, tue: true, wed: true, thu: true, fri: true, sun: false, sat: false}, start_time: ~T[09:00:00], start_date: ~D[2016-01-01], end_time: ~T[18:00:00], end_date: nil, blocked_days: [], timezone: "America/Argentina/Buenos_Aires"}} == Schedule.load("{\"timezone\":\"America/Argentina/Buenos_Aires\",\"start_time\":\"09:00:00\",\"start_date\":\"2016-01-01\",\"end_time\":\"18:00:00\",\"end_date\":null,\"day_of_week\":[\"mon\",\"tue\",\"wed\",\"thu\",\"fri\"],\"blocked_days\":[]}")
    end

    test "should load end_date" do
      assert {:ok, %Schedule{day_of_week: %DayOfWeek{mon: true, tue: true, wed: true, thu: true, fri: true, sun: false, sat: false}, start_time: ~T[09:00:00], start_date: ~D[2016-01-01], end_time: ~T[18:00:00], end_date: ~D[2016-02-01], blocked_days: [], timezone: "America/Argentina/Buenos_Aires"}} == Schedule.load("{\"timezone\":\"America/Argentina/Buenos_Aires\",\"start_time\":\"09:00:00\",\"start_date\":\"2016-01-01\",\"end_time\":\"18:00:00\",\"end_date\":\"2016-02-01\",\"day_of_week\":[\"mon\",\"tue\",\"wed\",\"thu\",\"fri\"],\"blocked_days\":[]}")
    end

    test "should load without end_date for backward compatibility" do
      assert {:ok, %Schedule{day_of_week: %DayOfWeek{mon: true, tue: true, wed: true, thu: true, fri: true, sun: false, sat: false}, start_time: ~T[09:00:00], start_date: ~D[2016-01-01], end_time: ~T[18:00:00], end_date: nil, blocked_days: [], timezone: "America/Argentina/Buenos_Aires"}} == Schedule.load("{\"timezone\":\"America/Argentina/Buenos_Aires\",\"start_time\":\"09:00:00\",\"start_date\":\"2016-01-01\",\"end_time\":\"18:00:00\",\"day_of_week\":[\"mon\",\"tue\",\"wed\",\"thu\",\"fri\"],\"blocked_days\":[]}")
    end
  end
  describe "cast:" do
    test "shuld cast to itself" do
      assert {:ok, %Schedule{day_of_week: %DayOfWeek{}, start_time: ~T[09:00:00], end_time: ~T[18:00:00], blocked_days: [], timezone: "Etc/UTC"}} == Schedule.cast(Schedule.default())
    end
    test "should cast string times" do
      assert {
        :ok,
        %Schedule{day_of_week: %DayOfWeek{sun: true, mon: true, tue: true, wed: true, thu: true, fri: false, sat: true}, start_time: ~T[09:00:00], start_date: nil, end_date: nil, end_time: ~T[19:00:00], blocked_days: [], timezone: "Etc/UTC"}
      } == Schedule.cast(%{day_of_week: %{sun: true, mon: true, tue: true, wed: true, thu: true, fri: false, sat: true}, start_time: "09:00:00", start_date: nil, end_date: nil, end_time: "19:00:00", timezone: "Etc/UTC", blocked_days: []})
    end

    test "should cast string days" do
      assert {
        :ok,
        %Schedule{day_of_week: %DayOfWeek{sun: true, mon: true, tue: true, wed: true, thu: true, fri: false, sat: true}, start_time: ~T[09:00:00], start_date: nil, end_date: nil, end_time: ~T[19:00:00], blocked_days: [~D[2016-01-01], ~D[2017-02-03]], timezone: "Etc/UTC"}
      } == Schedule.cast(%{day_of_week: %{sun: true, mon: true, tue: true, wed: true, thu: true, fri: false, sat: true}, start_time: ~T[09:00:00], start_date: nil, end_date: nil, end_time: "19:00:00", timezone: "Etc/UTC", blocked_days: ["2016-01-01", "2017-02-03"]})
    end

    test "should cast string times with string keys" do
      assert {
        :ok,
        %Schedule{day_of_week: %DayOfWeek{sun: true, mon: true, tue: true, wed: true, thu: true, fri: false, sat: true}, start_time: ~T[09:00:00], start_date: nil, end_date: nil, end_time: ~T[19:00:00], blocked_days: [], timezone: "Etc/UTC"}
      } == Schedule.cast(%{"day_of_week" => %{"sun" => true, "mon" => true, "tue" => true, "wed" => true, "thu" => true, "fri" => false, "sat" => true}, "start_time" => "09:00:00", "start_date" => nil, "end_time" => "19:00:00", "end_date" => nil, "timezone" => "Etc/UTC"})
    end

    test "should cast string days with string keys" do
      assert {
        :ok,
        %Schedule{day_of_week: %DayOfWeek{sun: true, mon: true, tue: true, wed: true, thu: true, fri: false, sat: true}, start_date: nil, start_time: ~T[09:00:00], end_time: ~T[19:00:00], end_date: nil, blocked_days: [~D[2016-01-01], ~D[2017-02-03]], timezone: "Etc/UTC"}
      } == Schedule.cast(%{"day_of_week" => %{"sun" => true, "mon" => true, "tue" => true, "wed" => true, "thu" => true, "fri" => false, "sat" => true}, "start_time" => "09:00:00", "start_date" => nil, "end_time" => ~T[19:00:00], "end_date" => nil, "timezone" => "Etc/UTC", "blocked_days" => ["2016-01-01", "2017-02-03"]})
    end

    test "should cast a struct with string keys" do
      assert {
        :ok,
        %Schedule{day_of_week: %DayOfWeek{sun: true, mon: true, tue: true, wed: true, thu: true, fri: false, sat: true}, start_date: nil, start_time: ~T[09:00:00], end_time: ~T[19:00:00], end_date: nil, blocked_days: []}
      } == Schedule.cast(%{"day_of_week" => %{"sun" => true, "mon" => true, "tue" => true, "wed" => true, "thu" => true, "fri" => false, "sat" => true}, "start_time" => ~T[09:00:00], "start_date" => nil, "end_time" => ~T[19:00:00], "end_date" => nil})
    end

    test "should cast nil" do
      assert {:ok, @default_schedule} == Schedule.cast(nil)
    end
  end

  describe "next_available_date_time" do
    @schedule %Ask.Schedule{
      start_time: ~T[09:00:00],
      end_time: ~T[18:00:00],
      day_of_week: %Ask.DayOfWeek{sun: true, wed: true},
      timezone: "America/Argentina/Buenos_Aires",
      start_date: ~D[2017-03-03],
      blocked_days: [~D[2017-10-08]]
    }

    test "gets next available time: free slot" do
      # OK because 20hs UTC is 17hs GMT-03
      base = DateTime.from_naive!(~N[2017-03-05 20:00:00], "Etc/UTC")
      time = @schedule |> Schedule.next_available_date_time(base)
      assert time == base
    end

    test "gets next available time: this day, earlier" do
      # 9hs UTC is 6hs GMT-03
      base = DateTime.from_naive!(~N[2017-03-05 09:00:00], "Etc/UTC")
      time = @schedule |> Schedule.next_available_date_time(base)
      # 12hs UTC is 9hs GMT-03
      assert time == DateTime.from_naive!(~N[2017-03-05 12:00:00], "Etc/UTC")
    end

    test "gets next available time: this day, too late" do
      # 9hs UTC is 6hs GMT-03
      base = DateTime.from_naive!(~N[2017-03-05 22:00:00], "Etc/UTC")
      time = @schedule |> Schedule.next_available_date_time(base)
      # Next available day is Wednesday
      assert time == DateTime.from_naive!(~N[2017-03-08 12:00:00], "Etc/UTC")
    end

    test "gets next available time: unavaible day" do
      base = DateTime.from_naive!(~N[2017-03-06 15:00:00], "Etc/UTC")
      time = @schedule |> Schedule.next_available_date_time(base)
      assert time == DateTime.from_naive!(~N[2017-03-08 12:00:00], "Etc/UTC")
    end

    test "gets next available time: blocked day" do
      base = DateTime.from_naive!(~N[2017-10-08 13:00:00], "Etc/UTC")
      time = @schedule |> Schedule.next_available_date_time(base)
      assert time == DateTime.from_naive!(~N[2017-10-11 12:00:00], "Etc/UTC")
    end

    test "gets next available time: start date" do
      # Long before the start date
      base = DateTime.from_naive!(~N[2017-02-01 00:00:00], "Etc/UTC")
      time = @schedule |> Schedule.next_available_date_time(base)
      # The beginning of the first active window after the start date
      assert time == DateTime.from_naive!(~N[2017-03-05 12:00:00], "Etc/UTC")
    end
  end

  describe "Survey.last_window_ends_at/1" do
    setup do
      # The 2nd week of April 2021
      base_schedule = %Ask.Schedule{
        # Starts on Monday
        start_date: ~D[2021-04-12],
        # From Tuesday to Thursday
        day_of_week: %Ask.DayOfWeek{tue: true, wed: true, thu: true},
        # Wednesday is blocked (so only Tuesday and Thursday are available)
        blocked_days: [~D[2021-04-14]],
        # From 9 AM
        start_time: ~T[09:00:00],
        # To 6 PM
        end_time: ~T[18:00:00],
        # DateTime.from_naive! expects a time zone to put the NaiveDateTime in.
        # If the time zone is "Etc/UTC", it always succeeds.
        # Use "Etc/UTC" to avoid unnecessary timezone complications on these tests.
        timezone: "Etc/UTC"
      }
      {:ok, base_schedule: base_schedule}
    end

    test "if end_date is on Saturday, ends on Thursday at 18:00", %{base_schedule: base_schedule} do
      # end_date is on Saturday
      end_date = ~D[2021-04-17]
      schedule = %{base_schedule | end_date: end_date}

      time = Schedule.last_window_ends_at(schedule)

      # Ends on Thursday at 18:00
      assert time == DateTime.from_naive!(~N[2021-04-15 18:00:00], "Etc/UTC")
    end

    test "if end_date is on Thursday, ends on Thursday at 18:00", %{base_schedule: base_schedule} do
      # end_date is on Thursday
      end_date = ~D[2021-04-15]
      schedule = %{base_schedule | end_date: end_date}

      time = Schedule.last_window_ends_at(schedule)

      # Ends on Thrusday at 18:00
      assert time == DateTime.from_naive!(~N[2021-04-15 18:00:00], "Etc/UTC")
    end

    test "if end_date is on Wednesday, ends on Tuesday at 18:00", %{base_schedule: base_schedule} do
      # end_date is on Wedsnesday
      end_date = ~D[2021-04-14]
      schedule = %{base_schedule | end_date: end_date}

      time = Schedule.last_window_ends_at(schedule)

      # Ends on Tuesday at 18:00
      assert time == DateTime.from_naive!(~N[2021-04-13 18:00:00], "Etc/UTC")
    end

    test "if end_date is on Monday, it breaks", %{base_schedule: base_schedule} do
      # end_date is on Monday
      end_date = ~D[2021-04-12]
      schedule = %{base_schedule | end_date: end_date}

      # It breaks
      assert_raise(FunctionClauseError, "no function clause matching in Date.from_erl/2", fn ->
        Schedule.last_window_ends_at(schedule)
      end)
    end
  end

  describe "at_end_time" do
    test "bug with IVR schedule in Ecuador" do
      schedule = %Ask.Schedule{
        start_time: ~T[09:00:00],
        end_time: ~T[20:00:00],
        day_of_week: %Ask.DayOfWeek{sun: true, mon: true, tue: true, wed: true, thu: true, fri: true, sat: true},
        timezone: "America/Bogota", # The Ecuador survey actually used Bogota as timezone
        blocked_days: []
      }
      start_time = DateTime.from_naive!(~N[2019-12-08 00:37:06], "Etc/UTC") # Dates in Verboice are shown in UTC

      end_time = schedule
      |> Schedule.at_end_time(start_time)

      assert Elixir.Timex.equal?(end_time, DateTime.from_naive!(~N[2019-12-08 01:00:00], "Etc/UTC"))
    end

    test "bug with IVR schedule in Ecuador wouldn't happen in GMT+5" do
      schedule = %Ask.Schedule{
        start_time: ~T[09:00:00],
        end_time: ~T[20:00:00],
        day_of_week: %Ask.DayOfWeek{sun: true, mon: true, tue: true, wed: true, thu: true, fri: true, sat: true},
        timezone: "Etc/GMT+5",
        blocked_days: []
      }
      start_time = DateTime.from_naive!(~N[2019-12-08 00:37:06], "Etc/UTC") # Dates in Verboice are shown in UTC

      end_time = schedule
      |> Schedule.at_end_time(start_time)

      assert Elixir.Timex.equal?(end_time, DateTime.from_naive!(~N[2019-12-08 01:00:00], "Etc/UTC"))
    end
  end

  describe "start date" do
    test "is honored by intersect?" do
      {:ok, dt_out, _} = DateTime.from_iso8601("2021-02-11T12:00:00Z")
      {:ok, dt_in, _} = DateTime.from_iso8601("2021-02-25T12:00:00Z")
      schedule = %{Schedule.always() | start_date: ~D[2021-02-19]}

      dt_out_intersect? = Schedule.intersect?(schedule, dt_out)
      dt_in_intersect? = Schedule.intersect?(schedule, dt_in)

      refute dt_out_intersect?
      assert dt_in_intersect?
    end

    test "is honored by next_available_date_time" do
      {:ok, dt, _} = DateTime.from_iso8601("2021-02-11T00:00:00Z")
      schedule = %{Schedule.always() | start_date: ~D[2021-02-19], start_time: ~T[14:00:00]}

      next_available_date_time = Schedule.next_available_date_time(schedule, dt)
      {:ok, expected_next_available_date_time, _} = DateTime.from_iso8601("2021-02-19T14:00:00Z")

      assert next_available_date_time == expected_next_available_date_time
    end
  end
end
