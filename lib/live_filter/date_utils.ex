defmodule LiveFilter.DateUtils do
  @moduledoc """
  Date utility functions for LiveFilter.
  Handles date range calculations for presets and custom ranges.
  """

  @default_presets [
    :last_month,
    :last_30_days,
    :last_7_days,
    :yesterday,
    :today,
    :tomorrow,
    :next_7_days,
    :this_month,
    :next_30_days,
    :this_year
  ]

  @preset_labels %{
    overdue: "Overdue",
    today: "Today",
    tomorrow: "Tomorrow",
    yesterday: "Yesterday",
    last_7_days: "Last 7 days",
    next_7_days: "Next 7 days",
    last_30_days: "Last 30 days",
    next_30_days: "Next 30 days",
    this_month: "This month",
    last_month: "Last month",
    this_year: "This year"
  }

  @doc """
  Returns the default list of date presets in chronological order.
  """
  @spec default_presets() :: [atom()]
  def default_presets, do: @default_presets

  @doc """
  Returns a human-readable label for a preset.
  """
  @spec preset_label(atom()) :: String.t()
  def preset_label(preset), do: Map.get(@preset_labels, preset, Phoenix.Naming.humanize(preset))

  @doc """
  Parses a preset atom into a date range tuple `{start_date, end_date}`.

  Special cases:
  - `:overdue` returns `{nil, yesterday}` for open-ended past range
  """
  @spec parse_preset(atom()) :: {Date.t() | nil, Date.t() | nil}
  def parse_preset(preset), do: do_parse_preset(preset, Date.utc_today())

  defp do_parse_preset(:overdue, today), do: {nil, Date.add(today, -1)}
  defp do_parse_preset(:today, today), do: {today, today}
  defp do_parse_preset(:tomorrow, today), do: {Date.add(today, 1), Date.add(today, 1)}
  defp do_parse_preset(:yesterday, today), do: {Date.add(today, -1), Date.add(today, -1)}
  defp do_parse_preset(:last_7_days, today), do: {Date.add(today, -6), today}
  defp do_parse_preset(:next_7_days, today), do: {today, Date.add(today, 6)}
  defp do_parse_preset(:last_30_days, today), do: {Date.add(today, -29), today}
  defp do_parse_preset(:next_30_days, today), do: {today, Date.add(today, 29)}

  defp do_parse_preset(:this_month, today) do
    {%{today | day: 1}, %{today | day: Date.days_in_month(today)}}
  end

  defp do_parse_preset(:last_month, today) do
    prev_month_date = Date.add(%{today | day: 1}, -1)
    {%{prev_month_date | day: 1}, %{prev_month_date | day: Date.days_in_month(prev_month_date)}}
  end

  defp do_parse_preset(:this_year, today) do
    {%{today | month: 1, day: 1}, %{today | month: 12, day: 31}}
  end

  defp do_parse_preset(_preset, _today), do: {nil, nil}

  @doc """
  Generates weekly chunks for calendar display.
  Returns a list of weeks, where each week is a list of 7 dates.
  """
  @spec calendar_weeks(Date.t()) :: [[Date.t()]]
  def calendar_weeks(month) do
    first_day = %{month | day: 1}
    last_day = %{month | day: Date.days_in_month(month)}

    # Start from Sunday before the first day (day_of_week returns 1=Monday..7=Sunday)
    day_of_week = Date.day_of_week(first_day)
    # Convert to 0=Sunday..6=Saturday
    sunday_offset = rem(day_of_week, 7)
    start_date = Date.add(first_day, -sunday_offset)

    # End on Saturday after the last day
    last_day_of_week = Date.day_of_week(last_day)
    saturday_offset = rem(7 - rem(last_day_of_week, 7), 7)
    end_date = Date.add(last_day, saturday_offset)

    Date.range(start_date, end_date)
    |> Enum.to_list()
    |> Enum.chunk_every(7)
  end

  @doc """
  Formats a date for display in the filter chip.
  Handles both Date structs and ISO8601 strings.
  """
  @spec format_date(Date.t() | String.t() | nil) :: String.t()
  def format_date(nil), do: "..."
  def format_date(%Date{} = date), do: Calendar.strftime(date, "%b %-d, %Y")

  def format_date(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> Calendar.strftime(date, "%b %-d, %Y")
      _ -> date_str
    end
  end

  @doc """
  Formats a date range for display.
  Returns "Feb 14, 2026" for same-day ranges, "Feb 1 - Feb 14, 2026" for multi-day.
  Handles both Date structs and ISO8601 strings.
  """
  @spec format_range({Date.t() | String.t() | nil, Date.t() | String.t() | nil}) :: String.t()
  def format_range({nil, nil}), do: "Select dates"

  def format_range({nil, end_date}) do
    "Before #{format_date(end_date)}"
  end

  def format_range({start_date, nil}) do
    "After #{format_date(start_date)}"
  end

  def format_range({start_date, end_date}) do
    start_d = to_date(start_date)
    end_d = to_date(end_date)

    case {start_d, end_d} do
      {d, d} when not is_nil(d) ->
        format_date(start_date)

      {%Date{year: y}, %Date{year: y}} ->
        "#{Calendar.strftime(start_d, "%b %-d")} - #{format_date(end_date)}"

      _ ->
        "#{format_date(start_date)} - #{format_date(end_date)}"
    end
  end

  defp to_date(%Date{} = d), do: d
  defp to_date(nil), do: nil

  defp to_date(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  @doc """
  Checks if a date is selected (start or end of range).
  """
  @spec selected?(Date.t(), Date.t() | nil, Date.t() | nil) :: boolean()
  def selected?(date, start_date, end_date) do
    date == start_date || date == end_date
  end

  @doc """
  Checks if a date is within the selected range (exclusive of endpoints).
  """
  @spec in_range?(Date.t(), Date.t() | nil, Date.t() | nil) :: boolean()
  def in_range?(_date, nil, _end_date), do: false
  def in_range?(_date, _start_date, nil), do: false

  def in_range?(date, start_date, end_date) do
    Date.compare(date, start_date) in [:gt, :eq] &&
      Date.compare(date, end_date) in [:lt, :eq]
  end
end
