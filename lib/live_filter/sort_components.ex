defmodule LiveFilter.SortComponents do
  @moduledoc """
  Styled, overridable sort UI over the headless `LiveFilter.Sort` helpers.

  - `sort_header/1` — a drop-in sortable `<th>` content cell (tri-state click).
  - `sort_menu/1` — a standalone "Order by" dropdown.

  Both are pure function components: they render markup and emit a DOM event
  (default `"lf_sort"` / `"lf_sort_to"`) that the host LiveView handles by
  calling `LiveFilter.Sort.toggle/3` (or `put/4`) and patching the URL. Style via
  `class`, replace the inner markup via the inner slot, or skip these entirely
  and build your own header from the `LiveFilter.Sort` primitives.
  """
  use Phoenix.Component

  alias LiveFilter.Sort

  @doc """
  A sortable table header cell. Place inside your own `<th>`.

  ## Attributes
    * `:field` (required) - the public sort field atom
    * `:label` (required) - header text (ignored if an inner block is given)
    * `:sort` (required) - the current `%LiveFilter.Sort{}`
    * `:sortable_fields` - the `SortField` list (used only to echo into the event); optional
    * `:event` - phx-click event name (default `"lf_sort"`)
    * `:target` - optional phx-target
    * `:class` - extra classes on the button
  """
  attr(:field, :atom, required: true)
  attr(:label, :string, required: true)
  attr(:sort, LiveFilter.Sort, required: true)
  attr(:sortable_fields, :list, default: [])
  attr(:event, :string, default: "lf_sort")
  attr(:target, :any, default: nil)
  attr(:class, :string, default: nil)
  slot(:inner_block)

  def sort_header(assigns) do
    assigns = assign(assigns, :direction, Sort.direction_for(assigns.sort, assigns.field))

    ~H"""
    <button
      type="button"
      phx-click={@event}
      phx-value-field={@field}
      phx-target={@target}
      aria-sort={aria_sort(@direction)}
      class={["inline-flex items-center gap-1 cursor-pointer select-none", @class]}
    >
      <%= if @inner_block != [] do %>
        {render_slot(@inner_block)}
      <% else %>
        <span>{@label}</span>
      <% end %>
      <span class="text-xs opacity-70" aria-hidden="true">{indicator(@direction)}</span>
    </button>
    """
  end

  @doc """
  Standalone "Order by" dropdown for single-column sorting (Linear/Notion style).

  Lists `sortable_fields` as clean rows. Clicking an inactive field selects it with
  its `default_direction`; clicking the active field flips its direction. The active
  field shows a check and a contextual direction badge. A "No sort" row clears the
  sort when one is active.

  Field clicks emit `event` (default `"lf_sort_to"`) with `phx-value-field` and a
  pre-computed `phx-value-direction`. The "No sort" row emits `clear_event`
  (default `"lf_sort_clear"`). Wire both in the host LiveView (e.g. `Sort.put/4`
  and `Sort.clear/1`).

  ## Attributes
    * `:sortable_fields` (required) - list of `LiveFilter.SortField`
    * `:sort` (required) - the current `%LiveFilter.Sort{}`
    * `:id` - base DOM id for the dropdown hooks (default `"lf-sort-menu"`); pass a
      unique value if more than one sort menu is rendered on the same page
    * `:event` - field-select phx-click event name (default `"lf_sort_to"`)
    * `:clear_event` - "No sort" phx-click event name (default `"lf_sort_clear"`)
    * `:target` - optional phx-target
    * `:class` - extra classes on the trigger
  """
  attr(:sortable_fields, :list, required: true)
  attr(:sort, LiveFilter.Sort, required: true)
  attr(:id, :string, default: "lf-sort-menu")
  attr(:event, :string, default: "lf_sort_to")
  attr(:clear_event, :string, default: "lf_sort_clear")
  attr(:target, :any, default: nil)
  attr(:class, :string, default: nil)

  def sort_menu(assigns) do
    active = List.first(assigns.sort.entries)

    rows =
      Enum.map(assigns.sortable_fields, fn sf ->
        dir = Sort.direction_for(assigns.sort, sf.field)

        %{
          field: sf.field,
          label: sf.label,
          active?: dir != nil,
          current_dir: dir,
          emit_dir: if(dir, do: flip(dir), else: sf.default_direction)
        }
      end)

    assigns =
      assigns
      |> assign(:active, active)
      |> assign(:rows, rows)
      |> assign(:active_label, active_label(active, assigns.sortable_fields))

    ~H"""
    <div class="dropdown dropdown-bottom">
      <button
        type="button"
        tabindex="0"
        phx-hook="DropdownTrigger"
        id={"#{@id}-trigger"}
        aria-haspopup="listbox"
        aria-label="Sort options"
        class={[
          "btn btn-sm btn-ghost gap-1.5 cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-1",
          @class
        ]}
      >
        <%= if @active do %>
          <span class="text-base-content/60">Sort:</span>
          <span>{@active_label}</span>
          <span class={[dir_icon(@active.direction), "size-4 opacity-70"]} aria-hidden="true" />
        <% else %>
          <span class="hero-arrows-up-down-mini size-4 opacity-60" aria-hidden="true" />
          <span>Sort</span>
        <% end %>
      </button>

      <div
        class="dropdown-content bg-base-100 rounded-lg shadow-xl border border-base-300 z-[60] w-56 mt-1 p-1 pointer-events-auto"
        role="listbox"
      >
        <ul class="w-full space-y-0.5">
          <li :for={row <- @rows} role="presentation">
            <button
              type="button"
              phx-hook="DropdownItem"
              id={"#{@id}-#{row.field}"}
              data-event={@event}
              data-field={row.field}
              data-direction={row.emit_dir}
              data-close-on-select="true"
              role="option"
              aria-selected={to_string(row.active?)}
              class={[
                "flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm cursor-pointer hover:bg-base-200 focus-visible:bg-base-200 focus-visible:outline-none",
                row.active? && "bg-base-200/70"
              ]}
            >
              <span class={["flex-1", row.active? && "font-medium text-base-content"]}>
                {row.label}
              </span>
              <span
                :if={row.active?}
                class="flex items-center gap-1 text-sm font-medium text-base-content/60"
                aria-hidden="true"
              >
                <span class={[dir_icon(row.current_dir), "size-4"]} />{dir_label(row.current_dir)}
              </span>
            </button>
          </li>

          <li :if={@active} role="presentation" class="mt-1 border-t border-base-200 pt-1">
            <button
              type="button"
              phx-hook="DropdownItem"
              id={"#{@id}-clear"}
              data-event={@clear_event}
              data-close-on-select="true"
              role="option"
              class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm cursor-pointer text-base-content/60 hover:bg-base-200 hover:text-base-content focus-visible:bg-base-200 focus-visible:outline-none"
            >
              <span class="hero-x-mark-mini size-4 shrink-0" aria-hidden="true" /> Clear sort
            </button>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp aria_sort(:asc), do: "ascending"
  defp aria_sort(:desc), do: "descending"
  defp aria_sort(_), do: "none"

  defp indicator(:asc), do: "↑"
  defp indicator(:desc), do: "↓"
  defp indicator(_), do: "↕"

  defp flip(:asc), do: :desc
  defp flip(:desc), do: :asc

  defp dir_icon(:asc), do: "hero-arrow-up-mini"
  defp dir_icon(:desc), do: "hero-arrow-down-mini"
  defp dir_icon(_), do: "hero-arrows-up-down-mini"

  defp dir_label(:asc), do: "asc"
  defp dir_label(:desc), do: "desc"
  defp dir_label(_), do: ""

  defp active_label(nil, _fields), do: "—"

  defp active_label(%Sort.Entry{field: field}, fields) do
    case Enum.find(fields, &(&1.field == field)) do
      %{label: label} -> label
      _ -> Atom.to_string(field)
    end
  end
end
