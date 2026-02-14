defmodule LiveFilter.Inputs.MultiSelect do
  @moduledoc false
  use Phoenix.Component

  import LiveFilter.OptionHelpers, only: [resolve_options: 1, opt_value: 1, opt_label: 1]

  def render(assigns) do
    options = resolve_options(assigns.filter.config)
    selected = assigns.filter.value || []
    assigns = assign(assigns, options: options, selected: selected)

    ~H"""
    <div class="flex flex-col gap-1 max-h-48 overflow-y-auto">
      <%= for opt <- @options do %>
        <label class="label cursor-pointer justify-start gap-2 py-0.5">
          <input
            type="checkbox"
            class="checkbox checkbox-sm"
            checked={opt_value(opt) in @selected}
            phx-click="change_multi_value"
            phx-value-id={@filter.id}
            phx-value-values={encode_toggled(@selected, opt_value(opt))}
            phx-target={@myself}
          />
          <span class="label-text text-sm">{opt_label(opt)}</span>
        </label>
      <% end %>
    </div>
    """
  end

  defp encode_toggled(current, value) do
    toggled =
      if value in current do
        List.delete(current, value)
      else
        current ++ [value]
      end

    Enum.join(toggled, ",")
  end
end
