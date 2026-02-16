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

  alias LiveFilter.Components.{
    Boolean,
    Calendar,
    DateRange,
    Datetime,
    Helpers,
    MultiSelect,
    RadioGroup,
    Select
  }

  import OptionHelpers, only: [resolve_options: 1, opt_value_string: 1, opt_label: 1]
  import Helpers, only: [values_match?: 2, x_icon: 1]

  import DaisyUIComponents.Button

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
    |> assign_new(:theme, fn -> :neutral end)
    |> assign_new(:variant, fn -> :neutral end)
  end

  defp assign_filter_state(socket) do
    %{config: configs, filters: parent_filters} = socket.assigns.filter
    local_filters = socket.assigns[:local_filters] || []

    parent_fields = MapSet.new(parent_filters, & &1.field)
    local_fields = MapSet.new(local_filters, & &1.field)

    # Keep local filters that aren't overridden by parent
    new_local = Enum.reject(local_filters, &MapSet.member?(parent_fields, &1.field))

    # Add default_visible filters that aren't already present
    all_active_fields = MapSet.union(parent_fields, MapSet.new(new_local, & &1.field))
    default_visible_filters = build_default_visible_filters(configs, all_active_fields)

    # Combine all filters
    all_filters = parent_filters ++ new_local ++ default_visible_filters

    # Sort filters by their config order to maintain consistent positioning
    filters = sort_filters_by_config(all_filters, configs)
    available_fields = available_fields(configs, filters)

    # Ensure default_visible filters are always tracked locally (even if from parent)
    # This preserves them across clear_all when parent doesn't include them
    default_visible_from_parent =
      parent_filters
      |> Enum.filter(fn f ->
        f.config.default_visible and not MapSet.member?(local_fields, f.field)
      end)

    all_local = new_local ++ default_visible_filters ++ default_visible_from_parent

    assign(socket,
      configs: configs,
      filters: filters,
      local_filters: all_local,
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
  defp variant_class(:neutral), do: ""
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
      phx-hook="MaintainFocus"
      id={"always-on-#{@filter.id}"}
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

    # Select with :in/:not_in operator should render as multi-select
    is_select_multi =
      filter_type == :select and assigns.filter.operator in [:in, :not_in]

    assigns =
      assign(assigns, %{
        theme_classes: Theme.get_theme(assigns.theme),
        variant_class: variant_class(assigns.variant),
        is_dropdown: is_dropdown,
        is_select: filter_type == :select and not is_select_multi,
        is_select_multi: is_select_multi,
        is_multi_select: filter_type == :multi_select,
        is_boolean: filter_type == :boolean,
        is_date_range: filter_type in [:date_range, :datetime_range],
        is_datetime_range: filter_type == :datetime_range,
        is_datetime: filter_type == :datetime,
        is_radio_group_dropdown: is_radio_group_dropdown
      })
      |> assign_new(:show_calendar, fn -> false end)
      |> assign_new(:date_current_month, fn -> Date.utc_today() end)
      |> assign_new(:date_selecting_start, fn -> true end)
      |> assign_new(:date_temp_start, fn -> nil end)
      |> assign_new(:date_temp_end, fn -> nil end)
      |> assign_new(:datetime_current_month, fn -> Date.utc_today() end)

    # Command mode with dropdown filters needs separate dropdown triggers for operator and value
    if assigns.mode == :command and is_dropdown do
      render_command_chip(assigns)
    else
      render_basic_chip(assigns)
    end
  end

  # Command mode: operator and value are separate independent dropdowns
  defp render_command_chip(assigns) do
    ~H"""
    <div
      class={["flex items-center relative", @theme_classes.chip, @variant_class]}
      id={"filter-chip-#{@filter.id}"}
    >
      <div class={@theme_classes.field}>
        <.filter_icon filter={@filter} theme_classes={@theme_classes} />
        <span class="font-medium">{@filter.config.label}</span>
      </div>

      <.operator_dropdown filter={@filter} theme_classes={@theme_classes} myself={@myself} />

      <.value_dropdown
        filter={@filter}
        theme_classes={@theme_classes}
        select_search={@select_search}
        newly_added={@newly_added}
        is_select={@is_select}
        is_select_multi={@is_select_multi}
        is_multi_select={@is_multi_select}
        is_boolean={@is_boolean}
        is_radio_group_dropdown={@is_radio_group_dropdown}
        is_datetime={@is_datetime}
        is_date_range={@is_date_range}
        show_calendar={@show_calendar}
        date_current_month={@date_current_month}
        date_selecting_start={@date_selecting_start}
        date_temp_start={@date_temp_start}
        date_temp_end={@date_temp_end}
        datetime_current_month={@datetime_current_month}
        myself={@myself}
      />

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
    </div>
    """
  end

  # Basic mode: entire chip is one dropdown (or no dropdown for non-dropdown types)
  defp render_basic_chip(assigns) do
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

  # Independent operator dropdown for command mode
  defp operator_dropdown(assigns) do
    # Use filter's configured operators with labels from Operators module
    options =
      Enum.map(assigns.filter.config.operators, fn op ->
        {op, Operators.label(op)}
      end)

    assigns = assign(assigns, :options, options)

    ~H"""
    <div class="dropdown dropdown-bottom">
      <button
        type="button"
        tabindex="0"
        class={["flex items-center gap-1 pl-3.5 pr-1.5 text-base-content/70 hover:text-base-content hover:bg-base-200 cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-1"]}
        aria-label={"Change operator, current: #{Operators.label(@filter.operator)}"}
        aria-haspopup="listbox"
        phx-hook="DropdownTrigger"
        id={"operator-trigger-#{@filter.id}"}
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
                data-close-on-select="true"
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

  # Independent value dropdown for command mode
  defp value_dropdown(assigns) do
    ~H"""
    <div
      id={"value-dropdown-#{@filter.id}"}
      class="dropdown dropdown-bottom focus-within:z-[100]"
      phx-hook={@newly_added && "AutoOpenDropdown"}
      phx-target={@myself}
    >
      <div
        class={[@theme_classes.values, !@filter.config.removable && "pr-2.5", "cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-1 rounded"]}
        tabindex="0"
        role="button"
        aria-haspopup="listbox"
        aria-label={"Select #{@filter.config.label} value"}
        phx-hook="DropdownTrigger"
        id={"value-trigger-#{@filter.id}"}
      >
        <.value_display_command filter={@filter} theme_classes={@theme_classes} />
      </div>

      <.select_dropdown :if={@is_select} filter={@filter} theme_classes={@theme_classes} select_search={@select_search} myself={@myself} />
      <.multi_select_dropdown :if={@is_select_multi or @is_multi_select} filter={@filter} theme_classes={@theme_classes} select_search={@select_search} myself={@myself} />
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
    </div>
    """
  end

  # Simplified value display for command mode (no cursor-pointer class, parent handles it)

  # Select with :in/:not_in operators - show multiple badges
  defp value_display_command(
         %{filter: %{config: %{type: :select}, operator: op, value: values}} = assigns
       )
       when op in [:in, :not_in] and is_list(values) and values != [] do
    ~H"""
    <div class="flex items-center gap-1 flex-wrap">
      <%= for val <- @filter.value do %>
        <span class={@theme_classes.badge}>
          {display_option_label(val, @filter.config)}
        </span>
      <% end %>
    </div>
    """
  end

  # Standard single-value select
  defp value_display_command(%{filter: %{config: %{type: :select}, value: value}} = assigns)
       when not is_nil(value) and value != "" do
    ~H"""
    <span class={@theme_classes.badge}>
      {display_option_label(@filter.value, @filter.config)}
    </span>
    """
  end

  defp value_display_command(
         %{filter: %{config: %{type: :multi_select}, value: values}} = assigns
       )
       when is_list(values) and values != [] do
    ~H"""
    <div class="flex items-center gap-1">
      <%= for val <- @filter.value do %>
        <span class={@theme_classes.badge}>
          {display_option_label(val, @filter.config)}
        </span>
      <% end %>
    </div>
    """
  end

  defp value_display_command(%{filter: %{config: %{type: :boolean}, value: value}} = assigns)
       when is_boolean(value) do
    config = assigns.filter.config
    assigns = assign(assigns, :label, if(value, do: config.true_label, else: config.false_label))

    ~H"""
    <span class={@theme_classes.badge}>
      {@label}
    </span>
    """
  end

  defp value_display_command(
         %{filter: %{config: %{type: :boolean, nullable: true}, value: nil}} = assigns
       ) do
    assigns = assign(assigns, :any_label, assigns.filter.config.any_label)

    ~H"""
    <span class={@theme_classes.badge}>
      {@any_label}
    </span>
    """
  end

  defp value_display_command(
         %{filter: %{config: %{type: type}, value: {start_val, end_val}}} = assigns
       )
       when type in [:date_range, :datetime_range] and
              (not is_nil(start_val) or not is_nil(end_val)) do
    assigns = assign(assigns, :display_range, DateUtils.format_range({start_val, end_val}))

    ~H"""
    <span class={@theme_classes.badge}>
      {@display_range}
    </span>
    """
  end

  defp value_display_command(
         %{filter: %{config: %{type: :datetime} = config, value: value}} = assigns
       )
       when not is_nil(value) and value != "" do
    formatted = Datetime.format_display(value, config.time_format)
    assigns = assign(assigns, :formatted, formatted)

    ~H"""
    <span class={@theme_classes.badge}>
      {@formatted}
    </span>
    """
  end

  defp value_display_command(
         %{filter: %{config: %{type: :radio_group} = config, value: value}} = assigns
       )
       when not is_nil(value) and value != "" do
    assigns = assign(assigns, :label, display_option_label(value, config))

    ~H"""
    <span class={@theme_classes.badge}>
      {@label}
    </span>
    """
  end

  defp value_display_command(%{filter: %{value: value}} = assigns)
       when not is_nil(value) and value != "" do
    ~H"""
    <span class={@theme_classes.badge}>{display_value_simple(@filter.value)}</span>
    """
  end

  defp value_display_command(assigns) do
    ~H"""
    <span class="text-base-content/60 text-sm italic">Select</span>
    """
  end

  defp select_dropdown(assigns) do
    Select.render(assigns)
  end

  defp multi_select_dropdown(assigns) do
    MultiSelect.render(assigns)
  end

  defp boolean_dropdown(assigns) do
    Boolean.render(assigns)
  end

  defp radio_group_dropdown(assigns) do
    RadioGroup.render(assigns)
  end

  defp radio_group_needs_dropdown?(%{type: :radio_group, style: :radios}), do: true

  defp radio_group_needs_dropdown?(%{type: :radio_group, style: :pills} = config) do
    options = resolve_options(config)
    length(options) > config.inline_threshold
  end

  defp radio_group_needs_dropdown?(_), do: false

  defp datetime_picker(assigns) do
    Datetime.render(assigns)
  end

  defp date_range_dropdown(assigns) do
    DateRange.render(assigns)
  end

  defp calendar_picker(assigns) do
    Calendar.render(assigns)
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
    formatted = Datetime.format_display(value, config.time_format)
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

  # Note: values_match?/2 is imported from Helpers

  defp display_value_simple(value) when is_binary(value), do: value
  defp display_value_simple(value) when is_number(value), do: to_string(value)
  defp display_value_simple(value), do: inspect(value)

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
  # Note: check_icon, x_icon, chevron_left_icon, chevron_right_icon are imported from Helpers

  defp plus_icon(assigns) do
    assigns = assign_new(assigns, :class, fn -> "shrink-0" end)

    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" class={@class} width="16" height="16" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
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
    filter = Enum.find(socket.assigns.filters, &(&1.id == filter_id))
    valid_operators = if filter, do: filter.config.operators, else: []

    case safe_to_existing_atom(op_str, valid_operators) do
      {:ok, new_op} ->
        apply_operator_change(socket, filter, filter_id, new_op)

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
      Datetime.parse_value(filter.value, filter.config.time_format)

    hour_24 =
      if filter.config.time_format == :twelve_hour do
        Datetime.to_24_hour(hour, period)
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
    # Keep always_on and default_visible filters, reset their values to defaults
    # Only remove user-added filters (neither always_on nor default_visible)
    baseline_filters =
      socket.assigns.filters
      |> Enum.filter(fn f -> f.config.always_on or f.config.default_visible end)
      |> Enum.map(fn f ->
        %{f | value: f.config.default_value, operator: f.config.default_operator}
      end)

    {:noreply, notify_parent(socket, baseline_filters)}
  end

  # --- Helpers ---

  defp update_datetime_time(socket, filter_id, updates) do
    filter = find_filter(socket.assigns.filters, filter_id)
    time_format = filter.config.time_format

    {current_date, current_hour, current_minute, current_period} =
      Datetime.parse_value(filter.value, time_format)

    # Use today if no date selected yet
    date = current_date || Date.utc_today()
    hour = Keyword.get(updates, :hour, current_hour)
    minute = Keyword.get(updates, :minute, current_minute)
    period = Keyword.get(updates, :period, current_period)

    hour_24 =
      if time_format == :twelve_hour do
        Datetime.to_24_hour(hour, period)
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
      {int, _} -> int
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
    Enum.any?(filters, fn f ->
      # Either it's a user-added filter (neither always_on nor default_visible)
      # OR it's a baseline filter with a non-default value
      is_user_added = not f.config.always_on and not f.config.default_visible
      is_user_added or has_non_default_value?(f)
    end)
  end

  defp has_non_default_value?(filter) do
    filter.value != filter.config.default_value or
      filter.operator != filter.config.default_operator
  end

  defp get_date_value(params, key) do
    case params do
      %{^key => val} when val not in [nil, ""] -> val
      _ -> nil
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

  # Valid preset atoms for date ranges
  defp valid_presets(filter) do
    (filter.config.date_presets || DateUtils.default_presets()) ++ [:overdue]
  end

  # Operator change helpers
  defp apply_operator_change(socket, filter, filter_id, new_op) do
    clear_value = Operators.value_mode(filter.operator) != Operators.value_mode(new_op)
    update_fn = &update_filter_operator(&1, new_op, clear_value)

    new_filters = update_filter(socket.assigns.filters, filter_id, update_fn)
    updated_filter = Enum.find(new_filters, &(&1.id == filter_id))

    if has_value?(updated_filter) do
      {:noreply, notify_parent(socket, new_filters)}
    else
      new_local = update_filter(socket.assigns.local_filters, filter_id, update_fn)
      {:noreply, assign(socket, filters: new_filters, local_filters: new_local)}
    end
  end

  defp update_filter_operator(filter, new_op, true = _clear),
    do: %{filter | operator: new_op, value: nil}

  defp update_filter_operator(filter, new_op, false), do: %{filter | operator: new_op}

  defp has_value?(%{value: val}) when val not in [nil, "", {nil, nil}, []], do: true
  defp has_value?(_), do: false
end
