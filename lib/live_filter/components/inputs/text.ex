defmodule LiveFilter.Inputs.Text do
  @moduledoc false
  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div class="relative">
      <input
        type="text"
        id={"filter-text-#{@filter.id}"}
        class="input input-bordered input-sm w-full pr-8"
        value={@filter.value || ""}
        data-server-value={@filter.value || ""}
        placeholder={@filter.config.placeholder || "Type to filter..."}
        phx-change="change_value"
        phx-debounce="300"
        phx-value-id={@filter.id}
        phx-target={@myself}
        name={"filter[#{@filter.id}]"}
      />
      <button
        :if={@filter.value && @filter.value != ""}
        type="button"
        aria-label="Clear search"
        tabindex="-1"
        class="absolute inset-y-0 right-2 flex items-center text-base-content/40 hover:text-base-content/70 transition-colors cursor-pointer"
        phx-click="clear_filter_value"
        phx-value-id={@filter.id}
        phx-target={@myself}
      >
        <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </div>
    """
  end
end
