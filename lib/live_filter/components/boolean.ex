defmodule LiveFilter.Components.Boolean do
  @moduledoc """
  Boolean dropdown component with three options: Any, Yes, No.

  Renders a DaisyUI dropdown with keyboard navigation and proper accessibility.
  Supports nullable booleans (with "Any" option) and non-nullable (Yes/No only).

  ## Required Assigns

  - `filter` - The Filter struct containing value (true/false/nil) and config
  - `myself` - The parent LiveComponent's @myself for event targeting

  ## Events (handled by parent)

  - `change_boolean` - %{"id" => filter_id, "value" => "true" | "false" | "any"}

  ## Example

      <LiveFilter.Components.Boolean.render
        filter={@filter}
        myself={@myself}
      />
  """
  use Phoenix.Component

  import LiveFilter.Components.Helpers, only: [check_icon: 1]

  @doc """
  Renders a boolean dropdown component.
  """
  attr(:filter, :map, required: true, doc: "The Filter struct")
  attr(:myself, :any, required: true, doc: "The parent LiveComponent's @myself")

  def render(assigns) do
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
            data-close-on-select="true"
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
            data-close-on-select="true"
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
            data-close-on-select="true"
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
end
