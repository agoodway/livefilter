defmodule LiveFilter.Inputs.Number do
  @moduledoc false
  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <input
      type="number"
      class="input input-bordered input-sm w-full"
      value={@filter.value || ""}
      placeholder={@filter.config.placeholder || "Enter number..."}
      phx-change="change_value"
      phx-debounce="300"
      phx-value-id={@filter.id}
      phx-target={@myself}
      name={"filter[#{@filter.id}]"}
    />
    """
  end
end
