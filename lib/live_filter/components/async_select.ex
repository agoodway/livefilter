defmodule LiveFilter.Components.AsyncSelect do
  @moduledoc """
  Dropdown async select component with server-side search.

  Renders a search input and results dropdown where options are
  fetched from the server via `search_fn` callbacks on the FilterConfig.

  ## Required Assigns

  - `filter` - The Filter struct containing value and config
  - `myself` - The parent LiveComponent's @myself for event targeting

  ## Optional Assigns

  - `async_search_text` - Map of filter_id => search string
  - `async_options` - Map of filter_id => list of {value, label} tuples

  ## Events (handled by parent)

  - `async_search` - %{"id" => filter_id, "value" => search_text}
  - `async_select_option` - %{"id" => filter_id, "value" => value, "label" => label}
  """
  use Phoenix.Component

  import LiveFilter.Components.Helpers, only: [check_icon: 1]

  attr(:filter, :map, required: true, doc: "The Filter struct")
  attr(:myself, :any, required: true, doc: "The parent LiveComponent's @myself")
  attr(:async_search_text, :map, default: %{}, doc: "Map of filter_id => search string")
  attr(:async_options, :map, default: %{}, doc: "Map of filter_id => [{value, label}]")

  def render(assigns) do
    search_text = Map.get(assigns.async_search_text, assigns.filter.id, "")
    options = Map.get(assigns.async_options, assigns.filter.id, [])
    config = assigns.filter.config
    show_results = String.length(search_text) >= config.min_chars

    assigns =
      assigns
      |> assign(:search_text, search_text)
      |> assign(:options, options)
      |> assign(:show_results, show_results)
      |> assign(:placeholder, config.placeholder || "Search...")
      |> assign(:empty_message, config.empty_message)
      |> assign(:debounce, config.debounce)

    ~H"""
    <div
      class="dropdown-content bg-base-100 rounded-lg shadow-xl border border-base-300 z-[60] w-full min-w-56 mt-1 pointer-events-auto"
      role="listbox"
      aria-label={@filter.config.label}
    >
      <div class="p-2">
        <input
          type="text"
          id={"async-search-#{@filter.id}"}
          class="input input-sm input-bordered w-full"
          placeholder={@placeholder}
          value={@search_text}
          phx-keyup="async_search"
          phx-value-id={@filter.id}
          phx-target={@myself}
          phx-debounce={@debounce}
          phx-hook="DropdownFocus"
          aria-label={"Search #{@filter.config.label}"}
          autocomplete="off"
        />
      </div>
      <ul :if={@show_results} class="p-2 max-h-80 overflow-y-auto">
        <%= for {{value, label}, idx} <- Enum.with_index(@options) do %>
          <li class="list-none" role="presentation">
            <button
              type="button"
              id={"async-opt-#{@filter.id}-#{idx}"}
              phx-hook="DropdownItem"
              data-event="async_select_option"
              data-id={@filter.id}
              data-value={value}
              data-label={label}
              data-close-on-select="true"
              phx-target={@myself}
              role="option"
              aria-selected={to_string(value == @filter.value)}
              class={[
                "flex items-center justify-between w-full px-3 py-2 text-left text-sm rounded-md cursor-pointer",
                "hover:bg-base-200 focus-visible:bg-base-200 focus-visible:outline-none",
                value == @filter.value && "bg-base-200"
              ]}
            >
              <span>{label}</span>
              <.check_icon :if={value == @filter.value} />
            </button>
          </li>
        <% end %>
        <li :if={@options == []} class="list-none text-center py-4 text-base-content/50 text-sm" role="presentation">
          {@empty_message}
        </li>
      </ul>
    </div>
    """
  end
end
