defmodule LiveFilter.Components.Calendar do
  @moduledoc """
  Two-month calendar picker for custom date range selection.

  Renders a DaisyUI dialog with two side-by-side calendar months,
  allowing selection of start and end dates for date range filters.

  ## Required Assigns

  - `filter` - The Filter struct
  - `myself` - The parent LiveComponent's @myself for event targeting
  - `current_month` - The left calendar's displayed month (Date)
  - `selecting_start` - Whether we're selecting start date (boolean)
  - `temp_start` - Temporarily selected start date (Date or nil)
  - `temp_end` - Temporarily selected end date (Date or nil)

  ## Events (handled by parent)

  - `select_calendar_date` - %{"id" => filter_id, "date" => iso_date}
  - `date_prev_month` - Navigate to previous month
  - `date_next_month` - Navigate to next month
  - `date_change_month` - Month dropdown change
  - `date_change_year` - Year dropdown change
  - `cancel_date_calendar` - Cancel and close

  ## Example

      <LiveFilter.Components.Calendar.render
        filter={@filter}
        myself={@myself}
        current_month={@current_month}
        selecting_start={@selecting_start}
        temp_start={@temp_start}
        temp_end={@temp_end}
      />
  """
  use Phoenix.Component

  alias LiveFilter.DateUtils

  import LiveFilter.Components.Helpers,
    only: [x_icon: 1, chevron_left_icon: 1, chevron_right_icon: 1]

  @doc """
  Renders a two-month calendar picker component.
  """
  attr(:filter, :map, required: true, doc: "The Filter struct")
  attr(:myself, :any, required: true, doc: "The parent LiveComponent's @myself")
  attr(:current_month, Date, required: true, doc: "The left calendar's displayed month")
  attr(:selecting_start, :boolean, required: true, doc: "Whether selecting start date")
  attr(:temp_start, Date, default: nil, doc: "Temporarily selected start date")
  attr(:temp_end, Date, default: nil, doc: "Temporarily selected end date")

  def render(assigns) do
    today = Date.utc_today()
    weeks = DateUtils.calendar_weeks(assigns.current_month)

    # Second month is next month
    next_month_date =
      Date.add(%{assigns.current_month | day: Date.days_in_month(assigns.current_month)}, 1)

    next_month_weeks = DateUtils.calendar_weeks(next_month_date)

    # Year range for dropdown (10 years back to 5 years forward)
    current_year = today.year
    years = (current_year - 10)..(current_year + 5)

    assigns =
      assigns
      |> assign(:today, today)
      |> assign(:weeks, weeks)
      |> assign(:next_month_date, next_month_date)
      |> assign(:next_month_weeks, next_month_weeks)
      |> assign(:years, years)
      |> assign(:months, [
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
      ])

    ~H"""
    <div
      class="dropdown-content bg-base-100 rounded-lg shadow-xl border border-base-300 z-[60] mt-1 p-4 pointer-events-auto"
      phx-click-away="cancel_date_calendar"
      phx-target={@myself}
    >
      <div class="flex items-center justify-between mb-3">
        <span class="text-sm font-medium text-base-content">
          {if @selecting_start, do: "Select start date", else: "Select end date"}
        </span>
        <button
          type="button"
          class="btn btn-ghost btn-xs"
          phx-click="cancel_date_calendar"
          phx-target={@myself}
        >
          <.x_icon />
        </button>
      </div>

      <div class="flex gap-4">
        <.calendar_month
          month={@current_month}
          weeks={@weeks}
          today={@today}
          temp_start={@temp_start}
          temp_end={@temp_end}
          filter={@filter}
          months={@months}
          years={@years}
          is_left={true}
          myself={@myself}
        />
        <.calendar_month
          month={@next_month_date}
          weeks={@next_month_weeks}
          today={@today}
          temp_start={@temp_start}
          temp_end={@temp_end}
          filter={@filter}
          months={@months}
          years={@years}
          is_left={false}
          myself={@myself}
        />
      </div>

      <div :if={@temp_start} class="mt-3 pt-3 border-t border-base-200 text-sm text-base-content/70">
        Selected: {DateUtils.format_range({@temp_start, @temp_end})}
      </div>
    </div>
    """
  end

  defp calendar_month(assigns) do
    ~H"""
    <div class="w-64">
      <div class="flex items-center justify-between mb-2">
        <button
          :if={@is_left}
          type="button"
          class="btn btn-ghost btn-xs p-1"
          phx-click="date_prev_month"
          phx-target={@myself}
          aria-label="Previous month"
        >
          <.chevron_left_icon />
        </button>
        <div :if={!@is_left} class="w-6"></div>

        <div class="flex items-center gap-1">
          <select
            class="select select-ghost select-xs w-24"
            phx-change="date_change_month"
            phx-target={@myself}
          >
            <%= for {num, name} <- @months do %>
              <option value={num} selected={num == @month.month}>{name}</option>
            <% end %>
          </select>
          <select
            class="select select-ghost select-xs w-20"
            phx-change="date_change_year"
            phx-target={@myself}
          >
            <%= for year <- @years do %>
              <option value={year} selected={year == @month.year}>{year}</option>
            <% end %>
          </select>
        </div>

        <button
          :if={!@is_left}
          type="button"
          class="btn btn-ghost btn-xs p-1"
          phx-click="date_next_month"
          phx-target={@myself}
          aria-label="Next month"
        >
          <.chevron_right_icon />
        </button>
        <div :if={@is_left} class="w-6"></div>
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
              temp_start={@temp_start}
              temp_end={@temp_end}
              filter={@filter}
              myself={@myself}
            />
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp calendar_day(assigns) do
    is_current_month = assigns.day.month == assigns.month.month
    is_today = assigns.day == assigns.today
    is_selected = DateUtils.selected?(assigns.day, assigns.temp_start, assigns.temp_end)
    is_in_range = DateUtils.in_range?(assigns.day, assigns.temp_start, assigns.temp_end)
    is_start = assigns.day == assigns.temp_start
    is_end = assigns.day == assigns.temp_end

    assigns =
      assigns
      |> assign(:is_current_month, is_current_month)
      |> assign(:is_today, is_today)
      |> assign(:is_selected, is_selected)
      |> assign(:is_in_range, is_in_range)
      |> assign(:is_start, is_start)
      |> assign(:is_end, is_end)

    ~H"""
    <button
      type="button"
      class={[
        "p-2 text-sm rounded transition-colors cursor-pointer",
        !@is_current_month && "text-base-content/30",
        @is_current_month && !@is_selected && !@is_in_range && "text-base-content hover:bg-base-200",
        @is_today && !@is_selected && "ring-1 ring-primary ring-inset",
        @is_in_range && !@is_selected && "bg-primary/10",
        @is_selected && "bg-primary text-primary-content",
        @is_start && "rounded-r-none",
        @is_end && "rounded-l-none",
        @is_in_range && !@is_start && !@is_end && "rounded-none"
      ]}
      phx-click="select_calendar_date"
      phx-value-id={@filter.id}
      phx-value-date={Date.to_iso8601(@day)}
      phx-target={@myself}
    >
      {@day.day}
    </button>
    """
  end
end
