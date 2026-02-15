defmodule LiveFilter.Bar do
  @moduledoc """
  LiveComponent that renders the filter bar UI.

  Supports two modes:
  - `:basic` (default) - Simple chips without operator selection
  - `:command` - Full chips with inline operator dropdown (Linear/Notion style)

  Manages local state for which filter is being edited and whether the
  field picker dropdown is open. Notifies the parent via
  `{:live_filter, :updated, params}` when filters change.
  """

  use Phoenix.LiveComponent

  alias LiveFilter.{DateUtils, Filter, Inputs, Operators, OptionHelpers, Params.Serializer, Theme}

  import OptionHelpers, only: [resolve_options: 1, opt_value_string: 1, opt_label: 1]

  import DaisyUIComponents.Button

  # Default threshold for showing search input in dropdowns
  @default_search_threshold 8

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       editing_filter_id: nil,
       local_filters: [],
       filter_menu_search: "",
       select_search: %{},
       newly_added_filter_id: nil,
       # Date range calendar state
       date_calendar_filter_id: nil,
       date_selecting_start: true,
       date_temp_start: nil,
       date_temp_end: nil,
       date_current_month: Date.utc_today()
     )}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_defaults()
     |> assign_filter_state()}
  end

  defp assign_defaults(socket) do
    socket
    |> assign_new(:mode, fn -> :basic end)
    |> assign_new(:theme, fn -> :default end)
    |> assign_new(:variant, fn -> :outline end)
  end

  defp assign_filter_state(socket) do
    %{config: configs, filters: parent_filters} = socket.assigns.filter
    local_filters = socket.assigns[:local_filters] || []

    parent_fields = MapSet.new(parent_filters, & &1.field)
    new_local = Enum.reject(local_filters, &MapSet.member?(parent_fields, &1.field))

    # Add default_visible filters that aren't already present
    all_active_fields = MapSet.union(parent_fields, MapSet.new(new_local, & &1.field))
    default_visible_filters = build_default_visible_filters(configs, all_active_fields)

    # Combine all filters
    all_filters = parent_filters ++ new_local ++ default_visible_filters

    # Sort filters by their config order to maintain consistent positioning
    filters = sort_filters_by_config(all_filters, configs)
    available_fields = available_fields(configs, filters)

    assign(socket,
      configs: configs,
      filters: filters,
      local_filters: new_local ++ default_visible_filters,
      available_fields: available_fields
    )
  end

  defp build_default_visible_filters(configs, active_fields) do
    configs
    |> Enum.filter(& &1.default_visible)
    |> Enum.reject(&MapSet.member?(active_fields, &1.field))
    |> Enum.map(&Filter.new/1)
  end

  # Sort filters: default_visible filters come first (in config order), then user-added filters (append order)
  defp sort_filters_by_config(filters, configs) do
    default_visible_fields =
      configs
      |> Enum.filter(& &1.default_visible)
      |> Enum.map(& &1.field)
      |> MapSet.new()

    config_order =
      configs
      |> Enum.filter(& &1.default_visible)
      |> Enum.with_index()
      |> Enum.map(fn {config, idx} -> {config.field, idx} end)
      |> Map.new()

    {default_filters, user_filters} =
      Enum.split_with(filters, fn filter ->
        MapSet.member?(default_visible_fields, filter.field)
      end)

    # Sort default_visible filters by config order, keep user filters in their current order
    sorted_default =
      Enum.sort_by(default_filters, fn filter ->
        Map.get(config_order, filter.field, 999)
      end)

    sorted_default ++ user_filters
  end

  defp available_fields(configs, filters) do
    active_fields = MapSet.new(filters, & &1.field)

    Enum.reject(configs, fn config ->
      config.always_on or config.default_visible or MapSet.member?(active_fields, config.field)
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-2" id={@id}>
      <.always_on_filter :for={filter <- always_on_filters(@filters)} filter={filter} myself={@myself} />

      <.filter_chip
        :for={filter <- removable_filters(@filters)}
        filter={filter}
        mode={filter_mode(filter, @mode)}
        theme={filter_theme(filter, @theme)}
        variant={@variant}
        editing={@editing_filter_id == filter.id}
        select_search={@select_search}
        newly_added={@newly_added_filter_id == filter.id}
        show_calendar={@date_calendar_filter_id == filter.id}
        date_current_month={@date_current_month}
        date_selecting_start={@date_selecting_start}
        date_temp_start={@date_temp_start}
        date_temp_end={@date_temp_end}
        myself={@myself}
      />

      <.add_filter_dropdown
        :if={@available_fields != []}
        id={@id}
        available_fields={@available_fields}
        search={@filter_menu_search}
        myself={@myself}
      />

      <.button :if={has_clearable_filters?(@filters)} ghost size="sm" class="cursor-pointer" phx-click="clear_all" phx-target={@myself}>
        Clear all
      </.button>
    </div>
    """
  end

  defp filter_mode(%{config: %{mode: mode}}, _bar_mode) when not is_nil(mode), do: mode
  defp filter_mode(_filter, bar_mode), do: bar_mode

  defp filter_theme(%{config: %{theme: theme}}, _bar_theme) when not is_nil(theme), do: theme
  defp filter_theme(_filter, bar_theme), do: bar_theme

  defp variant_class(:outline), do: "btn-outline"
  defp variant_class(:ghost), do: "btn-ghost"
  defp variant_class(:soft), do: "btn-soft"
  defp variant_class(custom) when is_binary(custom), do: custom
  defp variant_class(_), do: "btn-outline"

  # --- Sub-components ---

  defp always_on_filter(assigns) do
    ~H"""
    <form
      class="flex items-center gap-1"
      phx-change="filter_form_change"
      phx-target={@myself}
      phx-value-id={@filter.id}
    >
      <span :if={!@filter.config.hide_label} class="text-sm font-medium text-base-content/70">{@filter.config.label}</span>
      <.filter_input filter={@filter} myself={@myself} />
    </form>
    """
  end

  defp filter_chip(assigns) do
    filter_type = assigns.filter.config.type

    # RadioGroup: inline pills when options <= threshold, otherwise dropdown
    is_radio_group_dropdown = radio_group_needs_dropdown?(assigns.filter.config)

    is_dropdown =
      filter_type in [:select, :multi_select, :boolean, :date_range, :datetime_range, :datetime] or
        is_radio_group_dropdown

    assigns =
      assigns
      |> assign(:theme_classes, Theme.get_theme(assigns.theme))
      |> assign(:variant_class, variant_class(assigns.variant))
      |> assign(:is_dropdown, is_dropdown)
      |> assign(:is_select, filter_type == :select)
      |> assign(:is_multi_select, filter_type == :multi_select)
      |> assign(:is_boolean, filter_type == :boolean)
      |> assign(:is_date_range, filter_type in [:date_range, :datetime_range])
      |> assign(:is_datetime_range, filter_type == :datetime_range)
      |> assign(:is_datetime, filter_type == :datetime)
      |> assign(:is_radio_group_dropdown, is_radio_group_dropdown)
      |> assign_new(:show_calendar, fn -> false end)
      |> assign_new(:date_current_month, fn -> Date.utc_today() end)
      |> assign_new(:date_selecting_start, fn -> true end)
      |> assign_new(:date_temp_start, fn -> nil end)
      |> assign_new(:date_temp_end, fn -> nil end)
      |> assign_new(:datetime_current_month, fn -> Date.utc_today() end)

    ~H"""
    <div
      class={[@is_dropdown && "dropdown dropdown-bottom relative focus-within:z-[100]", @theme_classes.chip, @variant_class]}
      id={"filter-chip-#{@filter.id}"}
      phx-hook={@is_dropdown && @newly_added && "AutoOpenDropdown"}
      phx-target={@myself}
    >
      <div
        class="flex items-center focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-1 rounded"
        tabindex={@is_dropdown && "0"}
        role={@is_dropdown && "button"}
        aria-haspopup={@is_dropdown && "listbox"}
        aria-label={@is_dropdown && "#{@filter.config.label} filter"}
        phx-hook={@is_dropdown && "DropdownTrigger"}
        id={@is_dropdown && "trigger-#{@filter.id}"}
      >
        <div class={@theme_classes.field}>
          <.filter_icon filter={@filter} theme_classes={@theme_classes} />
          <span class="font-medium">{@filter.config.label}</span>
        </div>

        <.operator_section :if={@mode == :command} filter={@filter} theme_classes={@theme_classes} myself={@myself} />

        <div class={[@theme_classes.values, !@filter.config.removable && "pr-2.5"]}>
          <.value_display filter={@filter} theme_classes={@theme_classes} mode={@mode} myself={@myself} />
        </div>
      </div>

      <button
        :if={@filter.config.removable}
        type="button"
        class={[@theme_classes.remove, "relative z-10"]}
        phx-click="remove_filter"
        phx-value-id={@filter.id}
        phx-target={@myself}
        aria-label="Remove filter"
      >
        <.x_icon />
      </button>

      <.select_dropdown :if={@is_select} filter={@filter} theme_classes={@theme_classes} select_search={@select_search} myself={@myself} />
      <.multi_select_dropdown :if={@is_multi_select} filter={@filter} theme_classes={@theme_classes} select_search={@select_search} myself={@myself} />
      <.boolean_dropdown :if={@is_boolean} filter={@filter} theme_classes={@theme_classes} myself={@myself} />
      <.radio_group_dropdown :if={@is_radio_group_dropdown} filter={@filter} theme_classes={@theme_classes} myself={@myself} />
      <.datetime_picker :if={@is_datetime} filter={@filter} current_month={@datetime_current_month} myself={@myself} />
      <.date_range_dropdown :if={@is_date_range && !@show_calendar} filter={@filter} theme_classes={@theme_classes} myself={@myself} />
      <.calendar_picker
        :if={@is_date_range && @show_calendar}
        filter={@filter}
        current_month={@date_current_month}
        selecting_start={@date_selecting_start}
        temp_start={@date_temp_start}
        temp_end={@date_temp_end}
        myself={@myself}
      />
      <.inline_editor :if={@editing} filter={@filter} myself={@myself} />
    </div>
    """
  end

  defp select_dropdown(assigns) do
    options = resolve_options(assigns.filter.config)
    select_search_map = assigns[:select_search] || %{}
    search = Map.get(select_search_map, assigns.filter.id, "")
    search_lower = String.downcase(search)

    filtered_options =
      if search == "" do
        options
      else
        Enum.filter(options, fn opt ->
          String.contains?(String.downcase(to_string(opt_label(opt))), search_lower)
        end)
      end

    threshold = assigns.filter.config.search_threshold || @default_search_threshold
    show_search = length(options) >= threshold

    has_search_query = search != ""

    assigns =
      assigns
      |> assign(:options, filtered_options)
      |> assign(:search, search)
      |> assign(:show_search, show_search)
      |> assign(:has_search_query, has_search_query)

    ~H"""
    <div
      class="dropdown-content bg-base-100 rounded-lg shadow-xl border border-base-300 z-[60] w-full min-w-48 mt-1 pointer-events-auto"
      role="listbox"
      aria-label={@filter.config.label}
    >
      <div :if={@show_search} class="p-2 pb-0">
        <input
          type="text"
          id={"select-search-#{@filter.id}"}
          class="input input-sm input-bordered w-full"
          placeholder="Search..."
          value={@search}
          phx-keyup="select_search"
          phx-value-id={@filter.id}
          phx-target={@myself}
          phx-debounce="100"
          phx-hook="DropdownFocus"
          aria-label={"Search #{@filter.config.label} options"}
          autocomplete="off"
        />
      </div>
      <ul class="p-2 max-h-80 overflow-y-auto">
        <%= for {opt, idx} <- Enum.with_index(@options) do %>
          <li class="list-none" role="presentation">
            <button
              type="button"
              id={"select-opt-#{@filter.id}-#{idx}"}
              phx-hook="DropdownItem"
              data-event="select_option_value"
              data-id={@filter.id}
              data-selected={opt_value_string(opt)}
              phx-target={@myself}
              role="option"
              aria-selected={to_string(values_match?(opt_value_string(opt), @filter.value))}
              class={[
                "flex items-center justify-between w-full px-3 py-2 text-left text-sm rounded-md cursor-pointer",
                "hover:bg-base-200 focus-visible:bg-base-200 focus-visible:outline-none",
                values_match?(opt_value_string(opt), @filter.value) && "bg-base-200"
              ]}
            >
              <span>{opt_label(opt)}</span>
              <.check_icon :if={values_match?(opt_value_string(opt), @filter.value)} />
            </button>
          </li>
        <% end %>
        <li :if={@options == []} class="list-none text-center py-4 text-base-content/50 text-sm" role="presentation">
          {if @has_search_query, do: "No matches found", else: "No options"}
        </li>
      </ul>
    </div>
    """
  end

  defp multi_select_dropdown(assigns) do
    options = resolve_options(assigns.filter.config)
    selected = assigns.filter.value || []

    # Add search support (reusing existing select_search map)
    select_search_map = assigns[:select_search] || %{}
    search = Map.get(select_search_map, assigns.filter.id, "")
    search_lower = String.downcase(search)

    filtered_options =
      if search == "" do
        options
      else
        Enum.filter(options, fn opt ->
          String.contains?(String.downcase(to_string(opt_label(opt))), search_lower)
        end)
      end

    threshold = assigns.filter.config.search_threshold || @default_search_threshold
    show_search = length(options) >= threshold
    has_search_query = search != ""

    assigns =
      assigns
      |> assign(:options, filtered_options)
      |> assign(:selected, selected)
      |> assign(:search, search)
      |> assign(:show_search, show_search)
      |> assign(:has_search_query, has_search_query)

    ~H"""
    <div
      class="dropdown-content bg-base-100 rounded-lg shadow-xl border border-base-300 z-[60] w-full min-w-48 mt-1 pointer-events-auto"
      role="group"
      aria-label={"#{@filter.config.label} options"}
    >
      <div :if={@show_search} class="p-2 pb-0">
        <input
          type="text"
          id={"multi-search-#{@filter.id}"}
          class="input input-sm input-bordered w-full"
          placeholder="Search..."
          value={@search}
          phx-keyup="select_search"
          phx-value-id={@filter.id}
          phx-target={@myself}
          phx-debounce="100"
          phx-hook="DropdownFocus"
          aria-label={"Search #{@filter.config.label} options"}
          autocomplete="off"
        />
      </div>
      <ul class="p-2 max-h-80 overflow-y-auto">
        <%= for {opt, idx} <- Enum.with_index(@options) do %>
          <li class="list-none" role="presentation">
            <button
              type="button"
              id={"multi-opt-#{@filter.id}-#{idx}"}
              phx-hook="DropdownItem"
              data-event="toggle_multi_value"
              data-id={@filter.id}
              data-value={opt_value_string(opt)}
              phx-target={@myself}
              role="checkbox"
              aria-checked={to_string(opt_value_string(opt) in @selected)}
              class={[
                "flex items-center justify-between w-full px-3 py-2 text-left text-sm rounded-md cursor-pointer",
                "hover:bg-base-200 focus-visible:bg-base-200 focus-visible:outline-none",
                opt_value_string(opt) in @selected && "bg-base-200"
              ]}
            >
              <span>{opt_label(opt)}</span>
              <.check_icon :if={opt_value_string(opt) in @selected} />
            </button>
          </li>
        <% end %>
        <li :if={@options == []} class="list-none text-center py-4 text-base-content/50 text-sm" role="presentation">
          {if @has_search_query, do: "No matches found", else: "No options"}
        </li>
      </ul>
      <div :if={@selected != []} class="border-t border-base-200 p-2">
        <button
          type="button"
          id={"clear-multi-#{@filter.id}"}
          phx-hook="DropdownItem"
          data-event="clear_filter_value"
          data-id={@filter.id}
          phx-target={@myself}
          role="button"
          class="w-full px-3 py-2 text-left text-sm text-base-content/60 hover:bg-base-200 focus-visible:bg-base-200 focus-visible:outline-none rounded-md cursor-pointer"
        >
          Clear all
        </button>
      </div>
    </div>
    """
  end

  defp boolean_dropdown(assigns) do
    config = assigns.filter.config

    assigns =
      assigns
      |> assign(:true_label, config.true_label)
      |> assign(:false_label, config.false_label)
      |> assign(:any_label, config.any_label)
      |> assign(:nullable, config.nullable)

    ~H"""
    <div
      class="dropdown-content bg-base-100 rounded-lg shadow-xl border border-base-300 z-[60] w-full min-w-32 mt-1 pointer-events-auto"
      role="listbox"
      aria-label={@filter.config.label}
    >
      <ul class="p-2">
        <li :if={@nullable} class="list-none" role="presentation">
          <button
            type="button"
            id={"bool-any-#{@filter.id}"}
            phx-hook="DropdownItem"
            data-event="change_boolean"
            data-id={@filter.id}
            data-value="any"
            phx-target={@myself}
            role="option"
            aria-selected={to_string(@filter.value == nil)}
            class={[
              "flex items-center justify-between w-full px-3 py-2 text-left text-sm rounded-md cursor-pointer",
              "hover:bg-base-200 focus-visible:bg-base-200 focus-visible:outline-none",
              @filter.value == nil && "bg-base-200"
            ]}
          >
            <span>{@any_label}</span>
            <.check_icon :if={@filter.value == nil} />
          </button>
        </li>
        <li class="list-none" role="presentation">
          <button
            type="button"
            id={"bool-yes-#{@filter.id}"}
            phx-hook="DropdownItem"
            data-event="change_boolean"
            data-id={@filter.id}
            data-value="true"
            phx-target={@myself}
            role="option"
            aria-selected={to_string(@filter.value == true)}
            class={[
              "flex items-center justify-between w-full px-3 py-2 text-left text-sm rounded-md cursor-pointer",
              "hover:bg-base-200 focus-visible:bg-base-200 focus-visible:outline-none",
              @filter.value == true && "bg-base-200"
            ]}
          >
            <span>{@true_label}</span>
            <.check_icon :if={@filter.value == true} />
          </button>
        </li>
        <li class="list-none" role="presentation">
          <button
            type="button"
            id={"bool-no-#{@filter.id}"}
            phx-hook="DropdownItem"
            data-event="change_boolean"
            data-id={@filter.id}
            data-value="false"
            phx-target={@myself}
            role="option"
            aria-selected={to_string(@filter.value == false)}
            class={[
              "flex items-center justify-between w-full px-3 py-2 text-left text-sm rounded-md cursor-pointer",
              "hover:bg-base-200 focus-visible:bg-base-200 focus-visible:outline-none",
              @filter.value == false && "bg-base-200"
            ]}
          >
            <span>{@false_label}</span>
            <.check_icon :if={@filter.value == false} />
          </button>
        </li>
      </ul>
    </div>
    """
  end

  defp radio_group_dropdown(assigns) do
    config = assigns.filter.config
    options = resolve_options(config)
    style = config.style

    assigns =
      assigns
      |> assign(:options, options)
      |> assign(:style, style)

    ~H"""
    <div
      class="dropdown-content bg-base-100 rounded-lg shadow-xl border border-base-300 z-[60] w-full min-w-32 mt-1 pointer-events-auto"
      role="listbox"
      aria-label={@filter.config.label}
    >
      <div :if={@style == :pills} class="p-3">
        <div class="join" role="radiogroup" aria-label={@filter.config.label}>
          <%= for opt <- @options do %>
            <button
              type="button"
              class={[
                "join-item btn btn-sm",
                opt_value_string(opt) == @filter.value && "btn-active"
              ]}
              phx-click="change_radio_group"
              phx-value-id={@filter.id}
              phx-value-value={opt_value_string(opt)}
              phx-target={@myself}
              role="radio"
              aria-checked={to_string(opt_value_string(opt) == @filter.value)}
            >
              {opt_label(opt)}
            </button>
          <% end %>
        </div>
      </div>
      <ul :if={@style == :radios} class="p-2">
        <%= for {opt, idx} <- Enum.with_index(@options) do %>
          <li class="list-none" role="presentation">
            <label class="flex items-center gap-2 px-3 py-2 rounded-md cursor-pointer hover:bg-base-200">
              <input
                type="radio"
                class="radio radio-sm"
                id={"radio-#{@filter.id}-#{idx}"}
                checked={opt_value_string(opt) == @filter.value}
                phx-click="change_radio_group"
                phx-value-id={@filter.id}
                phx-value-value={opt_value_string(opt)}
                phx-target={@myself}
                name={"radio-#{@filter.id}"}
              />
              <span class="text-sm">{opt_label(opt)}</span>
            </label>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  defp radio_group_needs_dropdown?(%{type: :radio_group, style: :radios}), do: true

  defp radio_group_needs_dropdown?(%{type: :radio_group, style: :pills} = config) do
    options = resolve_options(config)
    length(options) > config.inline_threshold
  end

  defp radio_group_needs_dropdown?(_), do: false

  defp datetime_picker(assigns) do
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
                <.datetime_calendar_day
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

  defp datetime_calendar_day(assigns) do
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

  defp to_24_hour(12, :am), do: 0
  defp to_24_hour(12, :pm), do: 12
  defp to_24_hour(hour, :am), do: hour
  defp to_24_hour(hour, :pm), do: hour + 12

  defp format_datetime_display(value, time_format) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, ndt} -> format_datetime_display(ndt, time_format)
      _ -> value
    end
  end

  defp format_datetime_display(%NaiveDateTime{} = ndt, time_format) do
    date_str = Calendar.strftime(ndt, "%b %d, %Y")

    time_str =
      if time_format == :twelve_hour do
        Calendar.strftime(ndt, "%I:%M %p")
      else
        Calendar.strftime(ndt, "%H:%M")
      end

    "#{date_str} #{time_str}"
  end

  defp format_datetime_display(_, _), do: ""

  defp date_range_dropdown(assigns) do
    # Get presets from config, default to standard set
    presets = assigns.filter.config.date_presets || DateUtils.default_presets()
    has_value = assigns.filter.value != nil and assigns.filter.value != {nil, nil}

    # Check if current value matches a preset (for highlighting)
    current_preset = get_current_preset(assigns.filter.value, presets)

    assigns =
      assigns
      |> assign(:presets, presets)
      |> assign(:has_value, has_value)
      |> assign(:current_preset, current_preset)

    ~H"""
    <div
      class="dropdown-content bg-base-100 rounded-lg shadow-xl border border-base-300 z-[60] w-full min-w-48 mt-1 pointer-events-auto"
      role="listbox"
      aria-label={@filter.config.label}
    >
      <ul class="p-2">
        <%= for {preset, idx} <- Enum.with_index(@presets) do %>
          <li class="list-none" role="presentation">
            <button
              type="button"
              id={"date-preset-#{@filter.id}-#{idx}"}
              phx-hook="DropdownItem"
              data-event="select_date_preset"
              data-id={@filter.id}
              data-preset={preset}
              phx-target={@myself}
              role="option"
              aria-selected={to_string(@current_preset == preset)}
              class={[
                "flex items-center justify-between w-full px-3 py-2 text-left text-sm rounded-md cursor-pointer",
                "hover:bg-base-200 focus-visible:bg-base-200 focus-visible:outline-none",
                @current_preset == preset && "bg-base-200"
              ]}
            >
              <span>{DateUtils.preset_label(preset)}</span>
              <.check_icon :if={@current_preset == preset} />
            </button>
          </li>
        <% end %>
        <li class="list-none border-t border-base-200 mt-2 pt-2" role="presentation">
          <button
            type="button"
            id={"date-custom-#{@filter.id}"}
            phx-hook="DropdownItem"
            data-event="show_date_calendar"
            data-id={@filter.id}
            phx-target={@myself}
            role="option"
            aria-selected={to_string(@has_value && @current_preset == nil)}
            class={[
              "flex items-center justify-between w-full px-3 py-2 text-left text-sm rounded-md cursor-pointer",
              "hover:bg-base-200 focus-visible:bg-base-200 focus-visible:outline-none",
              @has_value && @current_preset == nil && "bg-base-200"
            ]}
          >
            <span>Custom range...</span>
            <.check_icon :if={@has_value && @current_preset == nil} />
          </button>
        </li>
        <li :if={@has_value} class="list-none border-t border-base-200 mt-2 pt-2" role="presentation">
          <button
            type="button"
            id={"date-clear-#{@filter.id}"}
            phx-hook="DropdownItem"
            data-event="clear_filter_value"
            data-id={@filter.id}
            phx-target={@myself}
            role="option"
            class="w-full px-3 py-2 text-left text-sm text-base-content/60 rounded-md cursor-pointer hover:bg-base-200 focus-visible:bg-base-200 focus-visible:outline-none"
          >
            Clear filter
          </button>
        </li>
      </ul>
    </div>
    """
  end

  defp calendar_picker(assigns) do
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

  defp value_display(%{filter: %{config: %{type: :select}, value: value}} = assigns)
       when not is_nil(value) and value != "" do
    ~H"""
    <span class={[@theme_classes.badge, "cursor-pointer"]}>
      {display_option_label(@filter.value, @filter.config)}
    </span>
    """
  end

  defp value_display(%{filter: %{config: %{type: :multi_select}, value: values}} = assigns)
       when is_list(values) and values != [] do
    ~H"""
    <div class="flex items-center gap-1 cursor-pointer">
      <%= for val <- @filter.value do %>
        <span class={@theme_classes.badge}>
          {display_option_label(val, @filter.config)}
        </span>
      <% end %>
    </div>
    """
  end

  defp value_display(%{filter: %{config: %{type: :multi_select}}} = assigns) do
    ~H"""
    <span class="text-base-content/60 text-sm italic cursor-pointer">Select</span>
    """
  end

  # RadioGroup - inline pills when options <= inline_threshold
  defp value_display(
         %{filter: %{config: %{type: :radio_group, style: :pills} = config}} = assigns
       ) do
    options = resolve_options(config)
    inline_threshold = config.inline_threshold

    if length(options) <= inline_threshold do
      assigns = assign(assigns, :options, options)

      ~H"""
      <div class="join" role="radiogroup" aria-label={@filter.config.label}>
        <%= for opt <- @options do %>
          <button
            type="button"
            class={[
              "join-item btn btn-xs",
              opt_value_string(opt) == @filter.value && "btn-active"
            ]}
            phx-click="change_radio_group"
            phx-value-id={@filter.id}
            phx-value-value={opt_value_string(opt)}
            phx-target={@myself}
            role="radio"
            aria-checked={to_string(opt_value_string(opt) == @filter.value)}
          >
            {opt_label(opt)}
          </button>
        <% end %>
      </div>
      """
    else
      assigns = assign(assigns, :label, display_option_label(assigns.filter.value, config))

      ~H"""
      <span class={[@theme_classes.badge, "cursor-pointer"]}>
        {@label}
      </span>
      """
    end
  end

  # RadioGroup - radios style always shows label (dropdown rendering)
  defp value_display(%{filter: %{config: %{type: :radio_group} = config, value: value}} = assigns)
       when not is_nil(value) and value != "" do
    assigns = assign(assigns, :label, display_option_label(value, config))

    ~H"""
    <span class={[@theme_classes.badge, "cursor-pointer"]}>
      {@label}
    </span>
    """
  end

  defp value_display(%{filter: %{config: %{type: :radio_group}}} = assigns) do
    ~H"""
    <span class="text-base-content/60 text-sm italic cursor-pointer">Select</span>
    """
  end

  defp value_display(%{filter: %{config: %{type: :boolean}, value: value}} = assigns)
       when is_boolean(value) do
    config = assigns.filter.config
    assigns = assign(assigns, :label, if(value, do: config.true_label, else: config.false_label))

    ~H"""
    <span class={[@theme_classes.badge, "cursor-pointer"]}>
      {@label}
    </span>
    """
  end

  # Nullable boolean with nil value - show "Any" label
  defp value_display(
         %{filter: %{config: %{type: :boolean, nullable: true}, value: nil}} = assigns
       ) do
    assigns = assign(assigns, :any_label, assigns.filter.config.any_label)

    ~H"""
    <span class={[@theme_classes.badge, "cursor-pointer"]}>
      {@any_label}
    </span>
    """
  end

  defp value_display(%{filter: %{config: %{type: :boolean}}} = assigns) do
    ~H"""
    <span class="text-base-content/60 text-sm italic cursor-pointer">Select</span>
    """
  end

  defp value_display(%{filter: %{config: %{type: type}, value: {start_val, end_val}}} = assigns)
       when type in [:date_range, :datetime_range] and
              (not is_nil(start_val) or not is_nil(end_val)) do
    assigns = assign(assigns, :display_range, DateUtils.format_range({start_val, end_val}))

    ~H"""
    <span class={[@theme_classes.badge, "cursor-pointer"]}>
      {@display_range}
    </span>
    """
  end

  defp value_display(%{filter: %{config: %{type: type}}} = assigns)
       when type in [:date_range, :datetime_range] do
    ~H"""
    <span class="text-base-content/60 text-sm italic cursor-pointer">Select</span>
    """
  end

  # DateTime with value - format nicely
  defp value_display(%{filter: %{config: %{type: :datetime} = config, value: value}} = assigns)
       when not is_nil(value) and value != "" do
    formatted = format_datetime_display(value, config.time_format)
    assigns = assign(assigns, :formatted, formatted)

    ~H"""
    <span class={[@theme_classes.badge, "cursor-pointer"]}>
      {@formatted}
    </span>
    """
  end

  defp value_display(%{filter: %{config: %{type: :datetime}}} = assigns) do
    ~H"""
    <span class="text-base-content/60 text-sm italic cursor-pointer">Select</span>
    """
  end

  # Number in command mode: show inline input
  # Hide native spinners for cleaner look - user types value directly
  defp value_display(%{filter: %{config: %{type: :number}}, mode: :command} = assigns) do
    ~H"""
    <form phx-change="filter_form_change" phx-target={@myself} phx-value-id={@filter.id} class="flex items-center pl-1">
      <input
        type="number"
        name={"filter[#{@filter.id}]"}
        value={@filter.value}
        placeholder="0"
        class="border-none bg-transparent text-center px-1 rounded text-sm w-12 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-1 [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
        phx-debounce="300"
      />
    </form>
    """
  end

  # Text in command mode: show inline input
  defp value_display(%{filter: %{config: %{type: :text}}, mode: :command} = assigns) do
    ~H"""
    <form phx-change="filter_form_change" phx-target={@myself} phx-value-id={@filter.id} class="flex items-center pl-1">
      <input
        type="text"
        name={"filter[#{@filter.id}]"}
        value={@filter.value}
        placeholder="value"
        class="border-none bg-transparent px-1 rounded text-sm w-24 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-1"
        phx-debounce="300"
      />
    </form>
    """
  end

  defp value_display(assigns) do
    ~H"""
    <.value_badges filter={@filter} theme_classes={@theme_classes} myself={assigns[:myself]} />
    """
  end

  defp operator_section(assigns) do
    options = Operators.options_for_type(assigns.filter.config.type)
    assigns = assign(assigns, :options, options)

    ~H"""
    <div class="dropdown">
      <button
        type="button"
        tabindex="0"
        class={[@theme_classes.operator, "flex items-center gap-1 border-l border-base-300 pl-2 cursor-pointer"]}
        aria-label={"Change operator, current: #{Operators.label(@filter.operator)}"}
      >
        <span>{Operators.label(@filter.operator)}</span>
      </button>
      <div
        class="dropdown-content bg-base-100 rounded-lg shadow-xl border border-base-300 z-[60] w-max mt-1 pointer-events-auto"
        role="listbox"
        aria-label="Select operator"
      >
        <ul class="p-2">
          <%= for {{op, label}, idx} <- Enum.with_index(@options) do %>
            <li class="list-none" role="presentation">
              <button
                type="button"
                id={"operator-#{@filter.id}-#{idx}"}
                phx-hook="DropdownItem"
                data-event="change_operator"
                data-id={@filter.id}
                data-operator={op}
                phx-target={@myself}
                role="option"
                aria-selected={to_string(op == @filter.operator)}
                class={[
                  "flex items-center w-full px-3 py-2 text-left text-sm rounded-md whitespace-nowrap cursor-pointer",
                  "hover:bg-base-200 focus-visible:bg-base-200 focus-visible:outline-none",
                  op == @filter.operator && "bg-base-200"
                ]}
              >
                {label}
              </button>
            </li>
          <% end %>
        </ul>
      </div>
    </div>
    """
  end

  defp filter_icon(%{filter: %{config: %{icon: icon}}} = assigns) when is_function(icon) do
    icon.(assigns)
  end

  defp filter_icon(%{filter: %{config: %{icon: icon}}} = assigns) when is_binary(icon) do
    ~H"""
    <.render_filter_icon icon={@filter.config.icon} class="size-4 shrink-0" />
    """
  end

  defp filter_icon(%{filter: %{config: %{icon: nil}}} = assigns) do
    ~H""
  end

  defp filter_icon(assigns) do
    ~H""
  end

  # Render filter icon - supports nil (no icon) or string (heroicon class name like "hero-folder")
  defp render_filter_icon(%{icon: nil} = assigns) do
    ~H""
  end

  defp render_filter_icon(%{icon: icon} = assigns) when is_binary(icon) do
    ~H"""
    <span class={[@icon, @class]} aria-hidden="true" />
    """
  end

  defp render_filter_icon(assigns) do
    ~H""
  end

  # --- Value Badges ---

  defp value_badges(%{filter: %{config: %{type: :multi_select}, value: values}} = assigns)
       when is_list(values) and values != [] do
    ~H"""
    <%= for val <- @filter.value do %>
      <span class={@theme_classes.badge}>
        {display_option_label(val, @filter.config)}
        <button
          type="button"
          class="hover:text-error ml-0.5 cursor-pointer"
          phx-click="remove_value"
          phx-value-id={@filter.id}
          phx-value-selected={val}
          phx-target={@myself}
          aria-label={"Remove #{display_option_label(val, @filter.config)}"}
        >×</button>
      </span>
    <% end %>
    """
  end

  defp value_badges(%{filter: %{config: %{type: :boolean}, value: value}} = assigns)
       when is_boolean(value) do
    ~H"""
    <span class={@theme_classes.badge}>{if @filter.value, do: "Yes", else: "No"}</span>
    """
  end

  defp value_badges(%{filter: %{config: %{type: type}, value: {start_val, end_val}}} = assigns)
       when type in [:date_range, :datetime_range] and
              (not is_nil(start_val) or not is_nil(end_val)) do
    assigns = assign(assigns, :display_range, DateUtils.format_range({start_val, end_val}))

    ~H"""
    <span class={@theme_classes.badge}>{@display_range}</span>
    """
  end

  defp value_badges(%{filter: %{value: value}} = assigns)
       when not is_nil(value) and value != "" do
    ~H"""
    <span class={@theme_classes.badge}>{display_value_simple(@filter.value)}</span>
    """
  end

  defp value_badges(assigns) do
    ~H"""
    <span class="text-base-content/60 text-sm italic">Select</span>
    """
  end

  defp display_option_label(value, %{options: options}) when is_list(options) do
    Enum.find_value(options, value, fn
      {label, opt_val} -> if values_match?(value, opt_val), do: label, else: nil
      opt_val -> if values_match?(value, opt_val), do: opt_val, else: nil
    end)
  end

  defp display_option_label(value, %{options_fn: fun}) when is_function(fun, 0) do
    options = fun.()
    display_option_label(value, %{options: options})
  end

  defp display_option_label(value, _config), do: value

  # Handle string/integer comparison (URL params come as strings)
  defp values_match?(a, b) when a == b, do: true
  defp values_match?(a, b) when is_binary(a) and is_integer(b), do: a == to_string(b)
  defp values_match?(a, b) when is_integer(a) and is_binary(b), do: to_string(a) == b
  defp values_match?(_, _), do: false

  defp display_value_simple(value) when is_binary(value), do: value
  defp display_value_simple(value) when is_number(value), do: to_string(value)
  defp display_value_simple(value), do: inspect(value)

  # Check if the current date range value matches any preset
  defp get_current_preset(nil, _presets), do: nil
  defp get_current_preset({nil, nil}, _presets), do: nil

  defp get_current_preset({start_val, end_val}, presets) do
    # Normalize values to Date structs for comparison
    start_date = to_date(start_val)
    end_date = to_date(end_val)

    Enum.find(presets, fn preset ->
      {preset_start, preset_end} = DateUtils.parse_preset(preset)
      preset_start == start_date && preset_end == end_date
    end)
  end

  defp to_date(nil), do: nil
  defp to_date(%Date{} = d), do: d

  defp to_date(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  # --- Add Filter Dropdown ---

  defp add_filter_dropdown(assigns) do
    filtered =
      if assigns.search == "" do
        assigns.available_fields
      else
        search_lower = String.downcase(assigns.search)

        Enum.filter(assigns.available_fields, fn config ->
          String.contains?(String.downcase(config.label), search_lower)
        end)
      end

    assigns = assign(assigns, :filtered_fields, filtered)

    ~H"""
    <div class="dropdown dropdown-bottom relative focus-within:z-[100]">
      <button
        tabindex="0"
        class="btn btn-sm btn-ghost gap-1 cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-1"
        aria-haspopup="listbox"
        aria-label="Add filter"
        phx-hook="DropdownTrigger"
        id="add-filter-trigger"
      >
        <.plus_icon />
        Add Filter
      </button>
      <div
        class="dropdown-content bg-base-100 rounded-lg shadow-xl border border-base-300 z-[60] w-full min-w-48 mt-1 pointer-events-auto"
        role="listbox"
        aria-label="Available filters"
      >
        <ul class="p-2 max-h-60 overflow-y-auto">
          <%= for config <- @filtered_fields do %>
            <li class="list-none" role="presentation">
              <button
                type="button"
                id={"add-filter-#{config.field}"}
                phx-hook="DropdownItem"
                data-event="add_filter"
                data-field={config.field}
                phx-target={@myself}
                role="option"
                class="flex items-center gap-2 w-full px-3 py-2 text-left text-sm rounded-md hover:bg-base-200 focus-visible:bg-base-200 focus-visible:outline-none cursor-pointer"
              >
                <.render_filter_icon icon={config.icon} class="w-4 h-4 text-base-content/60 shrink-0" />
                <span>{config.label}</span>
              </button>
            </li>
          <% end %>
          <li :if={@filtered_fields == []} class="list-none text-center py-4 text-base-content/50 text-sm" role="presentation">
            No options
          </li>
        </ul>
      </div>
    </div>
    """
  end

  # --- Inline Editor ---

  defp inline_editor(assigns) do
    ~H"""
    <form
      class="absolute top-full left-0 mt-1 p-3 shadow-lg bg-base-100 rounded-box border z-50 min-w-[240px]"
      phx-change="filter_form_change"
      phx-target={@myself}
      phx-value-id={@filter.id}
      phx-click-away="close_editor"
    >
      <div class="flex flex-col gap-2">
        <.operator_selector filter={@filter} myself={@myself} />
        <.filter_input filter={@filter} myself={@myself} />
      </div>
    </form>
    """
  end

  defp operator_selector(assigns) do
    options = Operators.options_for_type(assigns.filter.config.type)
    assigns = assign(assigns, :options, options)

    ~H"""
    <%= if length(@options) > 1 do %>
      <select class="select select-bordered select-xs w-full" name="operator">
        <%= for {op, label} <- @options do %>
          <option value={op} selected={op == @filter.operator}>{label}</option>
        <% end %>
      </select>
    <% end %>
    """
  end

  defp filter_input(%{filter: %{config: %{input_component: component}}} = assigns)
       when not is_nil(component) do
    component.render(assigns)
  end

  defp filter_input(%{filter: %{config: %{type: type}}} = assigns) do
    case type do
      :text -> Inputs.Text.render(assigns)
      :number -> Inputs.Number.render(assigns)
      :select -> Inputs.Select.render(assigns)
      :multi_select -> Inputs.MultiSelect.render(assigns)
      :date -> Inputs.Date.render(assigns)
      :date_range -> Inputs.DateRange.render(assigns)
      :datetime_range -> Inputs.DateRange.render(assigns)
      :datetime -> Inputs.DateTime.render(assigns)
      :boolean -> Inputs.Boolean.render(assigns)
    end
  end

  # --- Icons ---

  # SVGs use explicit width/height attributes as fallback for when Tailwind classes aren't available
  defp check_icon(assigns) do
    assigns = assign_new(assigns, :class, fn -> "shrink-0 text-base-content" end)

    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" class={@class} width="16" height="16" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
    </svg>
    """
  end

  defp x_icon(assigns) do
    assigns = assign_new(assigns, :class, fn -> "shrink-0" end)

    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" class={@class} width="14" height="14" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
    </svg>
    """
  end

  defp plus_icon(assigns) do
    assigns = assign_new(assigns, :class, fn -> "shrink-0" end)

    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" class={@class} width="16" height="16" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
    </svg>
    """
  end

  defp chevron_left_icon(assigns) do
    assigns = assign_new(assigns, :class, fn -> "shrink-0" end)

    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" class={@class} width="16" height="16" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
    </svg>
    """
  end

  defp chevron_right_icon(assigns) do
    assigns = assign_new(assigns, :class, fn -> "shrink-0" end)

    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" class={@class} width="16" height="16" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
    </svg>
    """
  end

  # --- Event Handlers ---

  @impl true
  def handle_event("add_filter", %{"field" => field_str}, socket) do
    valid_fields = Enum.map(socket.assigns.configs, & &1.field)

    with {:ok, field} <- safe_to_existing_atom(field_str, valid_fields),
         %{} = config <- Enum.find(socket.assigns.configs, &(&1.field == field)) do
      filter = Filter.new(config)
      new_local = [filter | socket.assigns.local_filters]
      new_filters = socket.assigns.filters ++ [filter]
      available = available_fields(socket.assigns.configs, new_filters)

      socket =
        socket
        |> assign(
          filters: new_filters,
          local_filters: new_local,
          available_fields: available,
          newly_added_filter_id: filter.id
        )

      {:noreply, socket}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("clear_newly_added", _params, socket) do
    {:noreply, assign(socket, newly_added_filter_id: nil)}
  end

  def handle_event("select_search", %{"id" => filter_id, "value" => value}, socket) do
    select_search = Map.put(socket.assigns.select_search, filter_id, value)
    {:noreply, assign(socket, select_search: select_search)}
  end

  def handle_event("remove_filter", %{"id" => filter_id}, socket) do
    new_filters = Enum.reject(socket.assigns.filters, &(&1.id == filter_id))

    socket =
      socket
      |> assign(editing_filter_id: nil)
      |> notify_parent(new_filters)

    {:noreply, socket}
  end

  def handle_event("remove_value", %{"id" => filter_id, "selected" => value}, socket) do
    new_filters =
      update_filter(socket.assigns.filters, filter_id, fn filter ->
        new_values = List.delete(filter.value || [], value)
        %{filter | value: new_values}
      end)

    {:noreply, notify_parent(socket, new_filters)}
  end

  def handle_event("edit_filter", %{"id" => filter_id}, socket) do
    editing_id =
      if socket.assigns.editing_filter_id == filter_id, do: nil, else: filter_id

    {:noreply, assign(socket, editing_filter_id: editing_id)}
  end

  def handle_event("close_editor", _params, socket) do
    {:noreply, assign(socket, editing_filter_id: nil)}
  end

  def handle_event("filter_form_change", %{"id" => filter_id} = params, socket) do
    new_filters =
      case {params["operator"], get_in(params, ["filter", filter_id])} do
        {nil, nil} ->
          socket.assigns.filters

        {op_str, _} when is_binary(op_str) ->
          case safe_to_existing_atom(op_str, valid_operators_for_filter(socket, filter_id)) do
            {:ok, op} -> update_filter(socket.assigns.filters, filter_id, &%{&1 | operator: op})
            :error -> socket.assigns.filters
          end

        {_, value} ->
          update_filter(socket.assigns.filters, filter_id, &%{&1 | value: value})
      end

    {:noreply, notify_parent(socket, new_filters)}
  end

  def handle_event("change_operator", %{"id" => filter_id, "operator" => op_str}, socket) do
    case safe_to_existing_atom(op_str, all_operators()) do
      {:ok, op} ->
        new_filters = update_filter(socket.assigns.filters, filter_id, &%{&1 | operator: op})
        filter = Enum.find(new_filters, &(&1.id == filter_id))

        case filter do
          %{value: val} when val not in [nil, "", {nil, nil}] ->
            {:noreply, notify_parent(socket, new_filters)}

          _ ->
            new_local =
              update_filter(socket.assigns.local_filters, filter_id, &%{&1 | operator: op})

            {:noreply, assign(socket, filters: new_filters, local_filters: new_local)}
        end

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("change_value", %{"id" => filter_id} = params, socket) do
    value = params["value"] || get_in(params, ["filter", filter_id])
    new_filters = update_filter(socket.assigns.filters, filter_id, &%{&1 | value: value})
    {:noreply, notify_parent(socket, new_filters)}
  end

  def handle_event("select_option_value", %{"id" => filter_id, "selected" => value}, socket) do
    new_filters = update_filter(socket.assigns.filters, filter_id, &%{&1 | value: value})
    select_search = Map.delete(socket.assigns.select_search, filter_id)
    {:noreply, socket |> assign(select_search: select_search) |> notify_parent(new_filters)}
  end

  def handle_event("change_multi_value", %{"id" => filter_id} = params, socket) do
    values = Map.get(params, "values", "") |> parse_multi_values()
    new_filters = update_filter(socket.assigns.filters, filter_id, &%{&1 | value: values})
    {:noreply, notify_parent(socket, new_filters)}
  end

  def handle_event("toggle_multi_value", %{"id" => filter_id, "value" => value}, socket) do
    new_filters =
      update_filter(socket.assigns.filters, filter_id, fn filter ->
        current = filter.value || []

        new_value =
          if value in current do
            List.delete(current, value)
          else
            current ++ [value]
          end

        %{filter | value: new_value}
      end)

    {:noreply, notify_parent(socket, new_filters)}
  end

  def handle_event("change_boolean", %{"id" => filter_id, "value" => value}, socket) do
    bool_val =
      case value do
        "true" -> true
        "false" -> false
        "any" -> nil
      end

    new_filters = update_filter(socket.assigns.filters, filter_id, &%{&1 | value: bool_val})
    {:noreply, notify_parent(socket, new_filters)}
  end

  def handle_event("clear_filter_value", %{"id" => filter_id}, socket) do
    new_filters = update_filter(socket.assigns.filters, filter_id, &%{&1 | value: nil})
    {:noreply, notify_parent(socket, new_filters)}
  end

  def handle_event("change_radio_group", %{"id" => filter_id, "value" => value}, socket) do
    new_filters = update_filter(socket.assigns.filters, filter_id, &%{&1 | value: value})
    {:noreply, notify_parent(socket, new_filters)}
  end

  # DateTime picker event handlers
  def handle_event("datetime_prev_month", %{"id" => _filter_id}, socket) do
    current = socket.assigns[:datetime_current_month] || Date.utc_today()
    new_month = Date.beginning_of_month(current) |> Date.add(-1) |> Date.beginning_of_month()
    {:noreply, assign(socket, :datetime_current_month, new_month)}
  end

  def handle_event("datetime_next_month", %{"id" => _filter_id}, socket) do
    current = socket.assigns[:datetime_current_month] || Date.utc_today()
    new_month = Date.end_of_month(current) |> Date.add(1) |> Date.beginning_of_month()
    {:noreply, assign(socket, :datetime_current_month, new_month)}
  end

  def handle_event("datetime_change_month", %{"id" => _filter_id, "value" => month_str}, socket) do
    current = socket.assigns[:datetime_current_month] || Date.utc_today()
    month = safe_to_integer(month_str, current.month)
    new_month = Date.new!(current.year, month, 1)
    {:noreply, assign(socket, :datetime_current_month, new_month)}
  end

  def handle_event("datetime_change_year", %{"id" => _filter_id, "value" => year_str}, socket) do
    current = socket.assigns[:datetime_current_month] || Date.utc_today()
    year = safe_to_integer(year_str, current.year)
    new_month = Date.new!(year, current.month, 1)
    {:noreply, assign(socket, :datetime_current_month, new_month)}
  end

  def handle_event("datetime_select_date", %{"id" => filter_id, "date" => date_str}, socket) do
    date = Date.from_iso8601!(date_str)
    filter = find_filter(socket.assigns.filters, filter_id)

    # Preserve existing time or use default
    {_old_date, hour, minute, period} =
      parse_datetime_value(filter.value, filter.config.time_format)

    hour_24 =
      if filter.config.time_format == :twelve_hour do
        to_24_hour(hour, period)
      else
        hour
      end

    datetime = NaiveDateTime.new!(date, Time.new!(hour_24, minute, 0))
    datetime_str = NaiveDateTime.to_iso8601(datetime)

    new_filters = update_filter(socket.assigns.filters, filter_id, &%{&1 | value: datetime_str})
    {:noreply, notify_parent(socket, new_filters)}
  end

  def handle_event("datetime_change_hour", %{"id" => filter_id, "hour" => hour_str}, socket) do
    hour = safe_to_integer(hour_str, 12)
    update_datetime_time(socket, filter_id, hour: hour)
  end

  def handle_event("datetime_change_minute", %{"id" => filter_id, "minute" => minute_str}, socket) do
    minute = safe_to_integer(minute_str, 0)
    update_datetime_time(socket, filter_id, minute: minute)
  end

  def handle_event("datetime_toggle_period", %{"id" => filter_id, "period" => period_str}, socket) do
    period = String.to_existing_atom(period_str)
    update_datetime_time(socket, filter_id, period: period)
  end

  def handle_event("change_date_range", %{"id" => filter_id} = params, socket) do
    start_val = get_date_value(params, "start")
    end_val = get_date_value(params, "end")

    new_filters =
      update_filter(socket.assigns.filters, filter_id, &%{&1 | value: {start_val, end_val}})

    {:noreply, notify_parent(socket, new_filters)}
  end

  def handle_event("select_date_preset", %{"id" => filter_id, "preset" => preset_str}, socket) do
    filter = Enum.find(socket.assigns.filters, &(&1.id == filter_id))

    with %{} <- filter,
         {:ok, preset} <- safe_to_existing_atom(preset_str, valid_presets(filter)) do
      {start_date, end_date} = DateUtils.parse_preset(preset)

      # For datetime_range, output full ISO8601 datetimes with time component
      {start_val, end_val} = format_range_value(filter.config.type, start_date, end_date)

      new_filters =
        update_filter(socket.assigns.filters, filter_id, &%{&1 | value: {start_val, end_val}})

      {:noreply, notify_parent(socket, new_filters)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("show_date_calendar", %{"id" => filter_id}, socket) do
    {:noreply,
     assign(socket,
       date_calendar_filter_id: filter_id,
       date_selecting_start: true,
       date_temp_start: nil,
       date_temp_end: nil,
       date_current_month: Date.utc_today()
     )}
  end

  def handle_event("cancel_date_calendar", _params, socket) do
    {:noreply,
     assign(socket,
       date_calendar_filter_id: nil,
       date_selecting_start: true,
       date_temp_start: nil,
       date_temp_end: nil
     )}
  end

  def handle_event("select_calendar_date", %{"id" => filter_id, "date" => date_str}, socket) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        handle_calendar_date_selection(
          socket,
          filter_id,
          date,
          socket.assigns.date_selecting_start
        )

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("date_prev_month", _params, socket) do
    current = socket.assigns.date_current_month
    prev_month = Date.add(%{current | day: 1}, -1)
    {:noreply, assign(socket, date_current_month: %{prev_month | day: 1})}
  end

  def handle_event("date_next_month", _params, socket) do
    current = socket.assigns.date_current_month
    next_month = Date.add(%{current | day: Date.days_in_month(current)}, 1)
    {:noreply, assign(socket, date_current_month: next_month)}
  end

  def handle_event("date_change_month", %{"value" => month_str}, socket) do
    current = socket.assigns.date_current_month
    month = safe_to_integer(month_str, current.month)
    {:noreply, assign(socket, date_current_month: %{current | month: month, day: 1})}
  end

  def handle_event("date_change_year", %{"value" => year_str}, socket) do
    current = socket.assigns.date_current_month
    year = safe_to_integer(year_str, current.year)
    {:noreply, assign(socket, date_current_month: %{current | year: year, day: 1})}
  end

  def handle_event("clear_all", _params, socket) do
    always_on = Enum.filter(socket.assigns.filters, & &1.config.always_on)
    {:noreply, notify_parent(socket, always_on)}
  end

  # --- Helpers ---

  defp update_datetime_time(socket, filter_id, updates) do
    filter = find_filter(socket.assigns.filters, filter_id)
    time_format = filter.config.time_format

    {current_date, current_hour, current_minute, current_period} =
      parse_datetime_value(filter.value, time_format)

    # Use today if no date selected yet
    date = current_date || Date.utc_today()
    hour = Keyword.get(updates, :hour, current_hour)
    minute = Keyword.get(updates, :minute, current_minute)
    period = Keyword.get(updates, :period, current_period)

    hour_24 =
      if time_format == :twelve_hour do
        to_24_hour(hour, period)
      else
        hour
      end

    datetime = NaiveDateTime.new!(date, Time.new!(hour_24, minute, 0))
    datetime_str = NaiveDateTime.to_iso8601(datetime)

    new_filters = update_filter(socket.assigns.filters, filter_id, &%{&1 | value: datetime_str})
    {:noreply, notify_parent(socket, new_filters)}
  end

  defp find_filter(filters, filter_id) do
    Enum.find(filters, &(&1.id == filter_id))
  end

  defp safe_to_integer(str, default) do
    case Integer.parse(str) do
      {int, ""} -> int
      {int, _rest} -> int
      :error -> default
    end
  end

  defp handle_calendar_date_selection(socket, _filter_id, date, true = _selecting_start) do
    {:noreply,
     assign(socket,
       date_temp_start: date,
       date_temp_end: nil,
       date_selecting_start: false
     )}
  end

  defp handle_calendar_date_selection(socket, filter_id, date, false = _selecting_start) do
    {start_date, end_date} = order_dates(socket.assigns.date_temp_start, date)

    start_val = Date.to_iso8601(start_date)
    end_val = Date.to_iso8601(end_date)

    new_filters =
      update_filter(socket.assigns.filters, filter_id, &%{&1 | value: {start_val, end_val}})

    socket =
      socket
      |> assign(
        date_calendar_filter_id: nil,
        date_selecting_start: true,
        date_temp_start: nil,
        date_temp_end: nil
      )
      |> notify_parent(new_filters)

    {:noreply, socket}
  end

  defp order_dates(start_date, end_date) do
    case Date.compare(end_date, start_date) do
      :lt -> {end_date, start_date}
      _ -> {start_date, end_date}
    end
  end

  defp update_filter(filters, id, fun) do
    Enum.map(filters, fn
      %{id: ^id} = f -> fun.(f)
      f -> f
    end)
  end

  # Format date range values based on filter type
  # For datetime_range: output full ISO8601 datetimes with time component
  # For date_range: output plain ISO8601 dates
  defp format_range_value(:datetime_range, start_date, end_date) do
    {date_to_start_of_day_iso(start_date), date_to_end_of_day_iso(end_date)}
  end

  defp format_range_value(_type, start_date, end_date) do
    {date_to_iso(start_date), date_to_iso(end_date)}
  end

  defp date_to_start_of_day_iso(nil), do: nil

  defp date_to_start_of_day_iso(date) do
    date |> DateTime.new!(~T[00:00:00], "Etc/UTC") |> DateTime.to_iso8601()
  end

  defp date_to_end_of_day_iso(nil), do: nil

  defp date_to_end_of_day_iso(date) do
    date |> DateTime.new!(~T[23:59:59], "Etc/UTC") |> DateTime.to_iso8601()
  end

  defp date_to_iso(nil), do: nil
  defp date_to_iso(date), do: Date.to_iso8601(date)

  defp notify_parent(socket, new_filters) do
    params = Serializer.to_params(new_filters)
    send(self(), {:live_filter, :updated, params})
    available = available_fields(socket.assigns.configs, new_filters)
    assign(socket, filters: new_filters, available_fields: available)
  end

  defp always_on_filters(filters), do: Enum.filter(filters, & &1.config.always_on)
  defp removable_filters(filters), do: Enum.reject(filters, & &1.config.always_on)

  defp has_clearable_filters?(filters) do
    Enum.any?(filters, fn f -> !f.config.always_on end)
  end

  defp get_date_value(params, key) do
    case Map.get(params, key) do
      nil -> nil
      "" -> nil
      val -> val
    end
  end

  defp parse_multi_values(""), do: []
  defp parse_multi_values(values) when is_binary(values), do: String.split(values, ",")
  defp parse_multi_values(values) when is_list(values), do: values

  # Safe atom conversion with validation against allowed values
  defp safe_to_existing_atom(str, valid_atoms) when is_binary(str) and is_list(valid_atoms) do
    valid_strings = Enum.map(valid_atoms, &Atom.to_string/1)

    if str in valid_strings do
      {:ok, String.to_existing_atom(str)}
    else
      :error
    end
  end

  # Get valid operators for a filter by its ID
  defp valid_operators_for_filter(socket, filter_id) do
    case Enum.find(socket.assigns.filters, &(&1.id == filter_id)) do
      %{config: %{type: type}} ->
        Operators.options_for_type(type) |> Keyword.keys()

      nil ->
        []
    end
  end

  # All supported operators across all filter types
  defp all_operators do
    [:eq, :neq, :gt, :gte, :lt, :lte, :like, :ilike, :in, :is, :is_null, :cs, :cd, :ov, :gte_lte]
  end

  # Valid preset atoms for date ranges
  defp valid_presets(filter) do
    (filter.config.date_presets || DateUtils.default_presets()) ++ [:overdue]
  end
end
