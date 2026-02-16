defmodule LiveFilter.Components.Datetime do
  @moduledoc """
  Datetime picker component with calendar and time selection.

  Renders a DaisyUI dropdown with a monthly calendar view and time inputs
  supporting both 12-hour and 24-hour formats.

  ## Required Assigns

  - `filter` - The Filter struct containing value and config
  - `myself` - The parent LiveComponent's @myself for event targeting
  - `current_month` - The currently displayed month (Date)

  ## Events (handled by parent)

  - `datetime_select_date` - %{"id" => filter_id, "date" => iso_date}
  - `datetime_change_hour` - %{"id" => filter_id, "hour" => hour}
  - `datetime_change_minute` - %{"id" => filter_id, "minute" => minute}
  - `datetime_toggle_period` - %{"id" => filter_id, "period" => "am" | "pm"}
  - `datetime_prev_month` - %{"id" => filter_id}
  - `datetime_next_month` - %{"id" => filter_id}
  - `datetime_change_month` - month change event
  - `datetime_change_year` - year change event
  - `clear_filter_value` - %{"id" => filter_id}

  ## Example

      <LiveFilter.Components.Datetime.render
        filter={@filter}
        myself={@myself}
        current_month={@current_month}
      />
  """
  use Phoenix.Component

  alias LiveFilter.DateUtils

  import LiveFilter.Components.Helpers, only: [chevron_left_icon: 1, chevron_right_icon: 1]

  @doc """
  Renders a datetime picker component.
  """
  attr(:filter, :map, required: true, doc: "The Filter struct")
  attr(:myself, :any, required: true, doc: "The parent LiveComponent's @myself")
  attr(:current_month, Date, required: true, doc: "The currently displayed month")

  def render(assigns) do
    config = assigns.filter.config
    current_value = assigns.filter.value
    time_format = config.time_format
    minute_step = config.minute_step
    today = Date.utc_today()

    # Parse existing datetime value or use defaults
    {current_date, hour, minute, period} = parse_datetime_value(current_value, time_format)

    # Build calendar data for single month
    month = assigns.current_month
    weeks = DateUtils.calendar_weeks(month)

    months = [
      {1, "Jan"},
      {2, "Feb"},
      {3, "Mar"},
      {4, "Apr"},
      {5, "May"},
      {6, "Jun"},
      {7, "Jul"},
      {8, "Aug"},
      {9, "Sep"},
      {10, "Oct"},
      {11, "Nov"},
      {12, "Dec"}
    ]

    current_year = Date.utc_today().year
    years = (current_year - 10)..(current_year + 10)

    assigns =
      assigns
      |> assign(:time_format, time_format)
      |> assign(:minute_step, minute_step)
      |> assign(:current_date, current_date)
      |> assign(:hour, hour)
      |> assign(:minute, minute)
      |> assign(:period, period)
      |> assign(:today, today)
      |> assign(:month, month)
      |> assign(:weeks, weeks)
      |> assign(:months, months)
      |> assign(:years, years)
      |> assign(:has_value, not is_nil(current_value) and current_value != "")

    ~H"""
    <div
      class="dropdown-content bg-base-100 rounded-lg shadow-xl border border-base-300 z-[60] mt-1 p-4 pointer-events-auto"
      role="dialog"
      aria-label={"#{@filter.config.label} picker"}
    >
      <div class="flex gap-4">
        <%!-- Calendar section --%>
        <div class="w-64">
          <div class="flex items-center justify-between mb-2">
            <button
              type="button"
              class="btn btn-ghost btn-xs p-1"
              phx-click="datetime_prev_month"
              phx-value-id={@filter.id}
              phx-target={@myself}
              aria-label="Previous month"
            >
              <.chevron_left_icon />
            </button>

            <div class="flex items-center gap-1">
              <select
                class="select select-ghost select-xs w-24"
                phx-change="datetime_change_month"
                phx-value-id={@filter.id}
                phx-target={@myself}
              >
                <%= for {num, name} <- @months do %>
                  <option value={num} selected={num == @month.month}>{name}</option>
                <% end %>
              </select>
              <select
                class="select select-ghost select-xs w-20"
                phx-change="datetime_change_year"
                phx-value-id={@filter.id}
                phx-target={@myself}
              >
                <%= for year <- @years do %>
                  <option value={year} selected={year == @month.year}>{year}</option>
                <% end %>
              </select>
            </div>

            <button
              type="button"
              class="btn btn-ghost btn-xs p-1"
              phx-click="datetime_next_month"
              phx-value-id={@filter.id}
              phx-target={@myself}
              aria-label="Next month"
            >
              <.chevron_right_icon />
            </button>
          </div>

          <div class="grid grid-cols-7 gap-0 text-center text-xs text-base-content/60 mb-1">
            <span>Su</span>
            <span>Mo</span>
            <span>Tu</span>
            <span>We</span>
            <span>Th</span>
            <span>Fr</span>
            <span>Sa</span>
          </div>

          <div class="grid grid-cols-7 gap-0">
            <%= for week <- @weeks do %>
              <%= for day <- week do %>
                <.calendar_day
                  day={day}
                  month={@month}
                  today={@today}
                  current_date={@current_date}
                  filter={@filter}
                  myself={@myself}
                />
              <% end %>
            <% end %>
          </div>
        </div>

        <%!-- Time section --%>
        <div class="border-l border-base-300 pl-4 min-w-32">
          <div class="text-sm font-medium mb-3 text-base-content/70">Time</div>

          <div class="flex items-center gap-2 mb-3">
            <input
              type="number"
              class="input input-bordered input-sm w-14 text-center [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
              value={@hour}
              min={if @time_format == :twelve_hour, do: 1, else: 0}
              max={if @time_format == :twelve_hour, do: 12, else: 23}
              phx-change="datetime_change_hour"
              phx-value-id={@filter.id}
              phx-target={@myself}
              name="hour"
              aria-label="Hour"
            />
            <span class="text-lg font-medium">:</span>
            <input
              type="number"
              class="input input-bordered input-sm w-14 text-center [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
              value={String.pad_leading(to_string(@minute), 2, "0")}
              min="0"
              max="59"
              step={@minute_step}
              phx-change="datetime_change_minute"
              phx-value-id={@filter.id}
              phx-target={@myself}
              name="minute"
              aria-label="Minute"
            />
          </div>

          <div :if={@time_format == :twelve_hour} class="join mb-4">
            <button
              type="button"
              class={["join-item btn btn-sm", @period == :am && "btn-active"]}
              phx-click="datetime_toggle_period"
              phx-value-id={@filter.id}
              phx-value-period="am"
              phx-target={@myself}
            >
              AM
            </button>
            <button
              type="button"
              class={["join-item btn btn-sm", @period == :pm && "btn-active"]}
              phx-click="datetime_toggle_period"
              phx-value-id={@filter.id}
              phx-value-period="pm"
              phx-target={@myself}
            >
              PM
            </button>
          </div>

          <button
            :if={@has_value}
            type="button"
            class="btn btn-ghost btn-sm w-full"
            phx-click="clear_filter_value"
            phx-value-id={@filter.id}
            phx-target={@myself}
          >
            Clear
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp calendar_day(assigns) do
    is_current_month = assigns.day.month == assigns.month.month
    is_today = assigns.day == assigns.today
    is_selected = assigns.day == assigns.current_date

    assigns =
      assigns
      |> assign(:is_current_month, is_current_month)
      |> assign(:is_today, is_today)
      |> assign(:is_selected, is_selected)

    ~H"""
    <button
      type="button"
      class={[
        "p-2 text-sm rounded transition-colors cursor-pointer",
        !@is_current_month && "text-base-content/30",
        @is_current_month && !@is_selected && "hover:bg-base-200",
        @is_today && !@is_selected && "font-bold text-primary",
        @is_selected && "bg-primary text-primary-content"
      ]}
      phx-click="datetime_select_date"
      phx-value-id={@filter.id}
      phx-value-date={@day}
      phx-target={@myself}
    >
      {@day.day}
    </button>
    """
  end

  # Helper functions for parsing datetime values

  defp parse_datetime_value(nil, time_format), do: {nil, default_hour(time_format), 0, :am}
  defp parse_datetime_value("", time_format), do: {nil, default_hour(time_format), 0, :am}

  defp parse_datetime_value(datetime_str, time_format) when is_binary(datetime_str) do
    case NaiveDateTime.from_iso8601(datetime_str) do
      {:ok, ndt} ->
        date = NaiveDateTime.to_date(ndt)
        {hour, minute} = {ndt.hour, ndt.minute}

        if time_format == :twelve_hour do
          {display_hour, period} = to_12_hour(hour)
          {date, display_hour, minute, period}
        else
          {date, hour, minute, :am}
        end

      _ ->
        {nil, default_hour(time_format), 0, :am}
    end
  end

  defp parse_datetime_value(%NaiveDateTime{} = ndt, time_format) do
    date = NaiveDateTime.to_date(ndt)
    {hour, minute} = {ndt.hour, ndt.minute}

    if time_format == :twelve_hour do
      {display_hour, period} = to_12_hour(hour)
      {date, display_hour, minute, period}
    else
      {date, hour, minute, :am}
    end
  end

  defp parse_datetime_value(_, time_format), do: {nil, default_hour(time_format), 0, :am}

  defp default_hour(:twelve_hour), do: 12
  defp default_hour(:twenty_four_hour), do: 0

  defp to_12_hour(0), do: {12, :am}
  defp to_12_hour(12), do: {12, :pm}
  defp to_12_hour(hour) when hour < 12, do: {hour, :am}
  defp to_12_hour(hour), do: {hour - 12, :pm}

  # Public helper functions for use by event handlers

  @doc """
  Parses a datetime value into component parts.
  Returns {date, hour, minute, period} tuple.
  """
  def parse_value(nil, time_format), do: {nil, default_hour(time_format), 0, :am}
  def parse_value("", time_format), do: {nil, default_hour(time_format), 0, :am}

  def parse_value(datetime_str, time_format) when is_binary(datetime_str) do
    case NaiveDateTime.from_iso8601(datetime_str) do
      {:ok, ndt} ->
        date = NaiveDateTime.to_date(ndt)
        {hour, minute} = {ndt.hour, ndt.minute}

        if time_format == :twelve_hour do
          {display_hour, period} = to_12_hour(hour)
          {date, display_hour, minute, period}
        else
          {date, hour, minute, :am}
        end

      _ ->
        {nil, default_hour(time_format), 0, :am}
    end
  end

  def parse_value(%NaiveDateTime{} = ndt, time_format) do
    date = NaiveDateTime.to_date(ndt)
    {hour, minute} = {ndt.hour, ndt.minute}

    if time_format == :twelve_hour do
      {display_hour, period} = to_12_hour(hour)
      {date, display_hour, minute, period}
    else
      {date, hour, minute, :am}
    end
  end

  def parse_value(_, time_format), do: {nil, default_hour(time_format), 0, :am}

  @doc """
  Converts 12-hour time to 24-hour format.
  """
  def to_24_hour(12, :am), do: 0
  def to_24_hour(12, :pm), do: 12
  def to_24_hour(hour, :am), do: hour
  def to_24_hour(hour, :pm), do: hour + 12

  @doc """
  Formats a datetime value for display.
  """
  def format_display(value, time_format) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, ndt} -> format_display(ndt, time_format)
      _ -> value
    end
  end

  def format_display(%NaiveDateTime{} = ndt, time_format) do
    date_str = Calendar.strftime(ndt, "%b %d, %Y")

    time_str =
      if time_format == :twelve_hour do
        Calendar.strftime(ndt, "%I:%M %p")
      else
        Calendar.strftime(ndt, "%H:%M")
      end

    "#{date_str} #{time_str}"
  end

  def format_display(_, _), do: ""
end
