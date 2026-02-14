defmodule LiveFilter.Inputs.Date do
  @moduledoc false
  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <input
      type="date"
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
