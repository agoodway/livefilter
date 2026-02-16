defmodule LiveFilter.Components.MultiSelect do
  @moduledoc """
  Multi-select dropdown component with search support.

  Renders a DaisyUI dropdown with checkboxes, keyboard navigation,
  search filtering, and a "Clear all" action.

  ## Required Assigns

  - `filter` - The Filter struct containing value (list) and config
  - `myself` - The parent LiveComponent's @myself for event targeting

  ## Optional Assigns

  - `select_search` - Map of filter_id => search string for filtering options

  ## Events (handled by parent)

  - `toggle_multi_value` - %{"id" => filter_id, "value" => value}
  - `select_search` - %{"id" => filter_id, "value" => search}
  - `clear_filter_value` - %{"id" => filter_id}

  ## Example

      <LiveFilter.Components.MultiSelect.render
        filter={@filter}
        myself={@myself}
        select_search={@select_search}
      />
  """
  use Phoenix.Component

  import LiveFilter.OptionHelpers, only: [resolve_options: 1, opt_value_string: 1, opt_label: 1]
  import LiveFilter.Components.Helpers, only: [check_icon: 1]

  @default_search_threshold 8

  @doc """
  Renders a multi-select dropdown component.
  """
  attr(:filter, :map, required: true, doc: "The Filter struct")
  attr(:myself, :any, required: true, doc: "The parent LiveComponent's @myself")
  attr(:select_search, :map, default: %{}, doc: "Map of filter_id => search string")

  def render(assigns) do
    options = resolve_options(assigns.filter.config)
    selected = assigns.filter.value || []

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
end
