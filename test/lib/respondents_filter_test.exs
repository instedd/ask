defmodule Ask.RespondentsFilterTest do
  use ExUnit.Case
  alias Ask.RespondentsFilter

  @dummy_disposition "my-disposition"
  @dummy_date "2020-06-02"

  setup_all do
    {:ok, %{date_format_string: RespondentsFilter.date_format_string()}}
  end

  test "parse disposition from q" do
    q = "disposition:#{@dummy_disposition}"

    filter = RespondentsFilter.parse(q)

    assert filter.disposition == @dummy_disposition
  end

  test "parse since from q", %{date_format_string: date_format_string} do
    q = "since:#{@dummy_date}"

    filter = RespondentsFilter.parse(q)

    assert filter.since == Timex.parse!(@dummy_date, date_format_string)
  end

  test "parse since and disposition", %{date_format_string: date_format_string} do
    q = "since:#{@dummy_date} disposition:#{@dummy_disposition}"

    filter = RespondentsFilter.parse(q)

    assert filter.since == Timex.parse!(@dummy_date, date_format_string)
    assert filter.disposition == @dummy_disposition

    # change the arguments order
    q = "disposition:#{@dummy_disposition} since:#{@dummy_date}"

    filter = RespondentsFilter.parse(q)

    assert filter.since == Timex.parse!(@dummy_date, date_format_string)
    assert filter.disposition == @dummy_disposition
  end

  test "parse when irrelevant stuffs", %{date_format_string: date_format_string} do
    q = "foo disposition:#{@dummy_disposition} bar since:#{@dummy_date} baz"

    filter = RespondentsFilter.parse(q)

    assert filter.since == Timex.parse!(@dummy_date, date_format_string)
    assert filter.disposition == @dummy_disposition

    # change the arguments order
    q = "disposition:#{@dummy_disposition} foo bar since:#{@dummy_date}"

    filter = RespondentsFilter.parse(q)

    assert filter.since == Timex.parse!(@dummy_date, date_format_string)
    assert filter.disposition == @dummy_disposition
  end

  test "put disposition when empty" do
    filter = %RespondentsFilter{}

    filter = RespondentsFilter.put_disposition(filter, @dummy_disposition)

    assert filter.disposition == @dummy_disposition
    refute filter.since
  end

  test "put disposition when since", %{date_format_string: date_format_string} do
    filter = %RespondentsFilter{since: Timex.parse!(@dummy_date, date_format_string)}

    filter = RespondentsFilter.put_disposition(filter, @dummy_disposition)

    assert filter.since == Timex.parse!(@dummy_date, date_format_string)
    assert filter.disposition == @dummy_disposition
  end

  test "put disposition when exists", %{date_format_string: date_format_string} do
    filter = %RespondentsFilter{disposition: "old-disposition", since: Timex.parse!(@dummy_date, date_format_string)}

    filter = RespondentsFilter.put_disposition(filter, @dummy_disposition)

    assert filter.since == Timex.parse!(@dummy_date, date_format_string)
    assert filter.disposition == @dummy_disposition
  end

  test "parse since when empty", %{date_format_string: date_format_string} do
    filter = %RespondentsFilter{}

    filter = RespondentsFilter.parse_since(filter, @dummy_date)

    assert filter.since == Timex.parse!(@dummy_date, date_format_string)
    refute filter.disposition
  end

  test "parse since when disposition", %{date_format_string: date_format_string} do
    filter = %RespondentsFilter{disposition: @dummy_disposition}

    filter = RespondentsFilter.parse_since(filter, @dummy_date)

    assert filter.since == Timex.parse!(@dummy_date, date_format_string)
    assert filter.disposition == @dummy_disposition
  end

  test "parse since when exists", %{date_format_string: date_format_string} do
    filter = %RespondentsFilter{disposition: @dummy_disposition, since: Timex.parse!("2019-01-01", date_format_string)}

    filter = RespondentsFilter.parse_since(filter, @dummy_date)

    assert filter.since == Timex.parse!(@dummy_date, date_format_string)
    assert filter.disposition == @dummy_disposition
  end
end
