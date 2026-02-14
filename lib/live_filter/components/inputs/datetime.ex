defmodule LiveFilter.Inputs.DateTime do
  @moduledoc false
  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <input
      type="datetime-local"
      class="input input-bordered input-sm w-full"
      value={@filter.value || ""}
      phx-change="change_value"
      phx-value-id={@filter.id}
      phx-target={@myself}
      name={"filter[#{@filter.id}]"}
    />
    """
  end
end
