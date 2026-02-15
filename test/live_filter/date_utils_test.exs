defmodule LiveFilter.DateUtilsTest do
  use ExUnit.Case

  alias LiveFilter.DateUtils

  describe "format_date/1" do
    test "returns '...' for nil" do
      assert DateUtils.format_date(nil) == "..."
    end

    test "formats Date struct" do
      assert DateUtils.format_date(~D[2026-02-15]) == "Feb 15, 2026"
      assert DateUtils.format_date(~D[2024-01-01]) == "Jan 1, 2024"
      assert DateUtils.format_date(~D[2025-12-25]) == "Dec 25, 2025"
    end

    test "formats DateTime struct" do
      {:ok, dt, _} = DateTime.from_iso8601("2026-02-15T10:30:00Z")
      assert DateUtils.format_date(dt) == "Feb 15, 2026"
    end

    test "formats ISO8601 date string" do
      assert DateUtils.format_date("2026-02-15") == "Feb 15, 2026"
      assert DateUtils.format_date("2024-01-01") == "Jan 1, 2024"
    end

    test "formats ISO8601 datetime string (with time component)" do
      assert DateUtils.format_date("2026-02-15T00:00:00Z") == "Feb 15, 2026"
      assert DateUtils.format_date("2026-02-15T23:59:59Z") == "Feb 15, 2026"
      assert DateUtils.format_date("2024-01-01T12:30:45Z") == "Jan 1, 2024"
    end

    test "returns unparseable strings as-is" do
      assert DateUtils.format_date("invalid") == "invalid"
      assert DateUtils.format_date("not-a-date") == "not-a-date"
    end
  end

  describe "format_range/1" do
    test "returns 'Select dates' for nil/nil tuple" do
      assert DateUtils.format_range({nil, nil}) == "Select dates"
    end

    test "formats open-ended range (start only)" do
      assert DateUtils.format_range({~D[2026-02-15], nil}) == "After Feb 15, 2026"
      assert DateUtils.format_range({"2026-02-15", nil}) == "After Feb 15, 2026"
    end

    test "formats open-ended range (end only)" do
      assert DateUtils.format_range({nil, ~D[2026-02-15]}) == "Before Feb 15, 2026"
      assert DateUtils.format_range({nil, "2026-02-15"}) == "Before Feb 15, 2026"
    end

    test "formats same-day range as single date" do
      assert DateUtils.format_range({~D[2026-02-15], ~D[2026-02-15]}) == "Feb 15, 2026"
      assert DateUtils.format_range({"2026-02-15", "2026-02-15"}) == "Feb 15, 2026"
    end

    test "formats same-year range with abbreviated start date" do
      assert DateUtils.format_range({~D[2026-01-01], ~D[2026-02-15]}) == "Jan 1 - Feb 15, 2026"
      assert DateUtils.format_range({"2026-01-01", "2026-02-15"}) == "Jan 1 - Feb 15, 2026"
    end

    test "formats cross-year range with full dates" do
      assert DateUtils.format_range({~D[2025-12-01], ~D[2026-02-15]}) ==
               "Dec 1, 2025 - Feb 15, 2026"
    end

    test "handles ISO8601 datetime strings (datetime_range values)" do
      assert DateUtils.format_range({"2026-01-17T00:00:00Z", "2026-02-15T23:59:59Z"}) ==
               "Jan 17 - Feb 15, 2026"
    end

    test "handles same-day datetime range" do
      assert DateUtils.format_range({"2026-02-15T00:00:00Z", "2026-02-15T23:59:59Z"}) ==
               "Feb 15, 2026"
    end

    test "handles cross-year datetime range" do
      assert DateUtils.format_range({"2025-12-01T00:00:00Z", "2026-02-15T23:59:59Z"}) ==
               "Dec 1, 2025 - Feb 15, 2026"
    end
  end

  describe "parse_preset/1" do
    test "today returns same start and end date" do
      {start_date, end_date} = DateUtils.parse_preset(:today)
      assert start_date == Date.utc_today()
      assert end_date == Date.utc_today()
    end

    test "yesterday returns previous day" do
      {start_date, end_date} = DateUtils.parse_preset(:yesterday)
      yesterday = Date.add(Date.utc_today(), -1)
      assert start_date == yesterday
      assert end_date == yesterday
    end

    test "last_7_days returns 7 day range ending today" do
      {start_date, end_date} = DateUtils.parse_preset(:last_7_days)
      today = Date.utc_today()
      assert end_date == today
      assert start_date == Date.add(today, -6)
    end

    test "last_30_days returns 30 day range ending today" do
      {start_date, end_date} = DateUtils.parse_preset(:last_30_days)
      today = Date.utc_today()
      assert end_date == today
      assert start_date == Date.add(today, -29)
    end

    test "unknown preset returns nil/nil" do
      assert DateUtils.parse_preset(:unknown) == {nil, nil}
    end
  end

  describe "selected?/3" do
    test "returns true when date matches start or end" do
      assert DateUtils.selected?(~D[2026-02-15], ~D[2026-02-15], ~D[2026-02-20])
      assert DateUtils.selected?(~D[2026-02-20], ~D[2026-02-15], ~D[2026-02-20])
    end

    test "returns false when date doesn't match start or end" do
      refute DateUtils.selected?(~D[2026-02-17], ~D[2026-02-15], ~D[2026-02-20])
    end
  end

  describe "in_range?/3" do
    test "returns true for dates within range" do
      assert DateUtils.in_range?(~D[2026-02-17], ~D[2026-02-15], ~D[2026-02-20])
      assert DateUtils.in_range?(~D[2026-02-15], ~D[2026-02-15], ~D[2026-02-20])
      assert DateUtils.in_range?(~D[2026-02-20], ~D[2026-02-15], ~D[2026-02-20])
    end

    test "returns false for dates outside range" do
      refute DateUtils.in_range?(~D[2026-02-14], ~D[2026-02-15], ~D[2026-02-20])
      refute DateUtils.in_range?(~D[2026-02-21], ~D[2026-02-15], ~D[2026-02-20])
    end

    test "returns false when start is nil" do
      refute DateUtils.in_range?(~D[2026-02-17], nil, ~D[2026-02-20])
    end

    test "returns false when end is nil" do
      refute DateUtils.in_range?(~D[2026-02-17], ~D[2026-02-15], nil)
    end
  end
end
