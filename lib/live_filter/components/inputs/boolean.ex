defmodule LiveFilter.Inputs.Boolean do
  @moduledoc false
  use Phoenix.Component

  def render(assigns) do
    checked = assigns.filter.value == true
    config = assigns.filter.config
    label = if checked, do: config.true_label, else: config.false_label

    assigns =
      assigns
      |> assign(:checked, checked)
      |> assign(:label, label)

    ~H"""
    <label class="label cursor-pointer justify-start gap-2">
      <input
        type="checkbox"
        class="toggle toggle-sm"
        checked={@checked}
        phx-click="change_boolean"
        phx-value-id={@filter.id}
        phx-value-value={to_string(!@checked)}
        phx-target={@myself}
      />
      <span class="label-text text-sm">{@label}</span>
    </label>
    """
  end
end
