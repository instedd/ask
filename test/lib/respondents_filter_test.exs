defmodule Ask.RespondentsFilterTest do
  use ExUnit.Case
  alias Ask.RespondentsFilter

  @dummy_disposition "my-disposition"
  @dummy_since "my-date"

  test "parse disposition" do
    q = "disposition:#{@dummy_disposition}"

    filter = RespondentsFilter.parse(q)

    assert filter.disposition == @dummy_disposition
  end

  test "parse since" do
    q = "since:#{@dummy_since}"

    filter = RespondentsFilter.parse(q)

    assert filter.since == @dummy_since
  end

  test "parse since and disposition" do
    q = "since:#{@dummy_since} disposition:#{@dummy_disposition}"

    filter = RespondentsFilter.parse(q)

    assert filter.since == @dummy_since
    assert filter.disposition == @dummy_disposition

    # change arguments order
    q = "disposition:#{@dummy_disposition} since:#{@dummy_since}"

    filter = RespondentsFilter.parse(q)

    assert filter.since == @dummy_since
    assert filter.disposition == @dummy_disposition

    # add irrelevant stuffs
    q = "foo disposition:#{@dummy_disposition} bar since:#{@dummy_since} baz"

    filter = RespondentsFilter.parse(q)

    assert filter.since == @dummy_since
    assert filter.disposition == @dummy_disposition
  end
end
