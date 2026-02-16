defmodule LiveFilter.Components.RadioGroup do
  @moduledoc """
  Radio group dropdown component supporting pills and radio button styles.

  Renders a DaisyUI dropdown with either pill buttons (join component) or
  traditional radio buttons with keyboard navigation and proper accessibility.

  ## Required Assigns

  - `filter` - The Filter struct containing value and config
  - `myself` - The parent LiveComponent's @myself for event targeting

  ## Events (handled by parent)

  - `change_radio_group` - %{"id" => filter_id, "value" => selected_value}

  ## Example

      <LiveFilter.Components.RadioGroup.render
        filter={@filter}
        myself={@myself}
      />
  """
  use Phoenix.Component

  import LiveFilter.OptionHelpers, only: [resolve_options: 1, opt_value_string: 1, opt_label: 1]

  @doc """
  Renders a radio group dropdown component.
  """
  attr(:filter, :map, required: true, doc: "The Filter struct")
  attr(:myself, :any, required: true, doc: "The parent LiveComponent's @myself")

  def render(assigns) do
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
end
