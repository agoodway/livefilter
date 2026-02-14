defmodule LiveFilter.Inputs.Select do
  @moduledoc false
  use Phoenix.Component

  import LiveFilter.OptionHelpers, only: [resolve_options: 1, opt_value: 1, opt_label: 1]

  def render(assigns) do
    options = resolve_options(assigns.filter.config)
    assigns = assign(assigns, :options, options)

    ~H"""
    <select
      class="select select-bordered select-sm w-full"
      phx-change="change_value"
      phx-value-id={@filter.id}
      phx-target={@myself}
      name={"filter[#{@filter.id}]"}
    >
      <option value="">Select...</option>
      <%= for opt <- @options do %>
        <option value={opt_value(opt)} selected={opt_value(opt) == @filter.value}>
          {opt_label(opt)}
        </option>
      <% end %>
    </select>
    """
  end
end
