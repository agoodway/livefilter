defmodule LiveFilter.Components.DateRange do
  @moduledoc """
  Date range dropdown component with presets.

  Renders a DaisyUI dropdown with date range presets (today, last 7 days, etc.)
  and a "Custom range..." option that opens the calendar picker.

  ## Required Assigns

  - `filter` - The Filter struct containing value and config
  - `myself` - The parent LiveComponent's @myself for event targeting

  ## Events (handled by parent)

  - `select_date_preset` - %{"id" => filter_id, "preset" => preset_atom}
  - `show_date_calendar` - %{"id" => filter_id}
  - `clear_filter_value` - %{"id" => filter_id}

  ## Example

      <LiveFilter.Components.DateRange.render
        filter={@filter}
        myself={@myself}
      />
  """
  use Phoenix.Component

  alias LiveFilter.DateUtils

  import LiveFilter.Components.Helpers, only: [check_icon: 1]

  @doc """
  Renders a date range dropdown component.
  """
  attr(:filter, :map, required: true, doc: "The Filter struct")
  attr(:myself, :any, required: true, doc: "The parent LiveComponent's @myself")

  def render(assigns) do
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
end
