defmodule LiveFilter.Inputs.RadioGroup do
  @moduledoc false
  use Phoenix.Component

  import LiveFilter.OptionHelpers,
    only: [resolve_options: 1, opt_value_string: 1, opt_label_display: 1]

  @doc """
  Renders a radio group as either pills (using DaisyUI join) or radio buttons.

  Used inside dropdowns when inline rendering is not appropriate.
  """
  def render(assigns) do
    config = assigns.filter.config
    options = resolve_options(config)
    style = config.style

    assigns =
      assigns
      |> assign(:options, options)
      |> assign(:style, style)

    if style == :pills do
      render_pills(assigns)
    else
      render_radios(assigns)
    end
  end

  defp render_pills(assigns) do
    ~H"""
    <div class="join" role="radiogroup" aria-label={@filter.config.label}>
      <%= for opt <- @options do %>
        <button
          type="button"
          class={[
            "join-item btn btn-xs",
            opt_value_string(opt) == @filter.value && "btn-active"
          ]}
          phx-click="change_radio_group"
          phx-value-id={@filter.id}
          phx-value-value={opt_value_string(opt)}
          phx-target={@myself}
          role="radio"
          aria-checked={to_string(opt_value_string(opt) == @filter.value)}
        >
          {opt_label_display(opt)}
        </button>
      <% end %>
    </div>
    """
  end

  defp render_radios(assigns) do
    ~H"""
    <div class="flex flex-col gap-1" role="radiogroup" aria-label={@filter.config.label}>
      <%= for opt <- @options do %>
        <label class="label cursor-pointer justify-start gap-2 py-0.5">
          <input
            type="radio"
            class="radio radio-sm"
            checked={opt_value_string(opt) == @filter.value}
            phx-click="change_radio_group"
            phx-value-id={@filter.id}
            phx-value-value={opt_value_string(opt)}
            phx-target={@myself}
            name={"radio-#{@filter.id}"}
          />
          <span class="label-text text-sm">{opt_label_display(opt)}</span>
        </label>
      <% end %>
    </div>
    """
  end
end
