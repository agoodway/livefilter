defmodule LiveFilter.Components.Select do
  @moduledoc """
  Dropdown select component with search support.

  Renders a DaisyUI dropdown with keyboard navigation, search filtering,
  and proper accessibility attributes.

  ## Required Assigns

  - `filter` - The Filter struct containing value and config
  - `myself` - The parent LiveComponent's @myself for event targeting

  ## Optional Assigns

  - `select_search` - Map of filter_id => search string for filtering options

  ## Events (handled by parent)

  - `select_option_value` - %{"id" => filter_id, "selected" => value}
  - `select_search` - %{"id" => filter_id, "value" => search}

  ## Example

      <LiveFilter.Components.Select.render
        filter={@filter}
        myself={@myself}
        select_search={@select_search}
      />
  """
  use Phoenix.Component

  import LiveFilter.OptionHelpers, only: [resolve_options: 1, opt_value_string: 1, opt_label: 1]
  import LiveFilter.Components.Helpers, only: [values_match?: 2, check_icon: 1]

  @default_search_threshold 8

  @doc """
  Renders a dropdown select component.
  """
  attr(:filter, :map, required: true, doc: "The Filter struct")
  attr(:myself, :any, required: true, doc: "The parent LiveComponent's @myself")
  attr(:select_search, :map, default: %{}, doc: "Map of filter_id => search string")

  def render(assigns) do
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
              data-close-on-select="true"
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
end
