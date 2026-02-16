defmodule LiveFilter.Paginator do
  @moduledoc """
  LiveComponent that renders pagination controls.

  Provides:
  - Page info text ("Showing 26-50 of 127")
  - Per-page selector dropdown
  - Prev/Next buttons
  - Configurable page number stepper

  Notifies the parent via `{:live_filter, :page_changed, params}` when pagination changes.

  ## Example

      <.live_component
        module={LiveFilter.Paginator}
        id="pagination"
        pagination={@pagination}
        max_pages={5}
      />

  Or using the convenience function:

      <LiveFilter.paginator pagination={@pagination} max_pages={5} />
  """

  use Phoenix.LiveComponent

  alias LiveFilter.{Pagination, Params.Serializer}

  import DaisyUIComponents.Button
  import DaisyUIComponents.Join

  @default_max_pages 5

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    pagination = assigns.pagination
    max_pages = Map.get(assigns, :max_pages, @default_max_pages)
    class = Map.get(assigns, :class, "")

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       page: Pagination.page(pagination),
       total_pages: Pagination.total_pages(pagination),
       has_prev: Pagination.has_prev?(pagination),
       has_next: Pagination.has_next?(pagination),
       start_item: Pagination.start_item(pagination),
       end_item: Pagination.end_item(pagination),
       max_pages: max_pages,
       class: class
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <nav
      role="navigation"
      aria-label="Pagination"
      class={["flex items-center justify-between flex-wrap gap-4", @class]}
    >
      <.page_info
        start_item={@start_item}
        end_item={@end_item}
        total_count={@pagination.total_count}
      />

      <div class="flex items-center gap-4">
        <.limit_selector
          pagination={@pagination}
          myself={@myself}
        />

        <div class="flex items-center gap-1">
          <.prev_button has_prev={@has_prev} myself={@myself} />

          <.page_stepper
            :if={@pagination.total_count}
            page={@page}
            total_pages={@total_pages}
            max_pages={@max_pages}
            myself={@myself}
          />

          <.next_button has_next={@has_next} myself={@myself} />
        </div>
      </div>
    </nav>
    """
  end

  defp page_info(assigns) do
    ~H"""
    <div class="text-sm text-base-content/70">
      <%= if @total_count && @total_count > 0 do %>
        Showing <span class="font-medium">{@start_item}</span>
        to <span class="font-medium">{@end_item}</span>
        of <span class="font-medium">{@total_count}</span> results
      <% else %>
        No results
      <% end %>
    </div>
    """
  end

  defp page_stepper(assigns) do
    buttons = page_buttons(assigns.page, assigns.total_pages, assigns.max_pages)
    assigns = assign(assigns, :buttons, buttons)

    ~H"""
    <.join>
      <%= for btn <- @buttons do %>
        <%= if btn == "..." do %>
          <span class="btn btn-sm join-item btn-disabled" aria-hidden="true">...</span>
        <% else %>
          <.button
            class="join-item"
            size="sm"
            phx-click="go_to_page"
            phx-value-page={btn}
            phx-target={@myself}
            active={btn == @page}
            aria-label={"Page #{btn}"}
            aria-current={if btn == @page, do: "page"}
          >
            {btn}
          </.button>
        <% end %>
      <% end %>
    </.join>
    """
  end

  defp page_buttons(_page, total_pages, _max_pages) when total_pages <= 0 do
    []
  end

  defp page_buttons(_page, total_pages, max_pages) when total_pages <= max_pages do
    Enum.to_list(1..total_pages)
  end

  defp page_buttons(page, total_pages, max_pages) do
    half = div(max_pages - 2, 2)

    cond do
      page <= half + 1 ->
        Enum.to_list(1..(max_pages - 2)) ++ ["...", total_pages]

      page >= total_pages - half ->
        start = total_pages - max_pages + 3
        [1, "..."] ++ Enum.to_list(start..total_pages)

      true ->
        [1, "..."] ++ Enum.to_list((page - half)..(page + half)) ++ ["...", total_pages]
    end
  end

  defp limit_selector(assigns) do
    ~H"""
    <form phx-change="change_limit" phx-target={@myself} class="flex items-center gap-2">
      <label for="limit-select" class="text-sm text-base-content/70">Show</label>
      <select
        id="limit-select"
        name="limit"
        class="select select-sm select-bordered"
      >
        <option
          :for={opt <- @pagination.limit_options}
          value={opt}
          selected={opt == @pagination.limit}
        >
          {opt}
        </option>
      </select>
    </form>
    """
  end

  defp prev_button(assigns) do
    ~H"""
    <.button
      size="sm"
      outline
      disabled={!@has_prev}
      phx-click="prev_page"
      phx-target={@myself}
      aria-label="Go to previous page"
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        class="size-4"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor"
        stroke-width="2"
        aria-hidden="true"
      >
        <path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7" />
      </svg>
    </.button>
    """
  end

  defp next_button(assigns) do
    ~H"""
    <.button
      size="sm"
      outline
      disabled={!@has_next}
      phx-click="next_page"
      phx-target={@myself}
      aria-label="Go to next page"
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        class="size-4"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor"
        stroke-width="2"
        aria-hidden="true"
      >
        <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7" />
      </svg>
    </.button>
    """
  end

  # --- Event Handlers ---

  @impl true
  def handle_event("go_to_page", %{"page" => page_str}, socket) do
    with {page, ""} <- Integer.parse(page_str),
         true <- page > 0 do
      new_pagination = Pagination.go_to_page(socket.assigns.pagination, page)
      notify_parent(new_pagination)
      {:noreply, socket}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("prev_page", _, socket) do
    new_pagination = Pagination.prev_page(socket.assigns.pagination)
    notify_parent(new_pagination)
    {:noreply, socket}
  end

  def handle_event("next_page", _, socket) do
    new_pagination = Pagination.next_page(socket.assigns.pagination)
    notify_parent(new_pagination)
    {:noreply, socket}
  end

  def handle_event("change_limit", %{"limit" => limit_str}, socket) do
    with {limit, ""} <- Integer.parse(limit_str),
         true <- limit > 0 do
      new_pagination = Pagination.change_limit(socket.assigns.pagination, limit)
      notify_parent(new_pagination)
      {:noreply, socket}
    else
      _ -> {:noreply, socket}
    end
  end

  defp notify_parent(pagination) do
    params = Serializer.pagination_to_params(pagination)
    send(self(), {:live_filter, :page_changed, params})
  end
end
