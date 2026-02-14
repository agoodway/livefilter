defmodule LiveFilter.Inputs.DateRange do
  @moduledoc false
  use Phoenix.Component

  def render(assigns) do
    {start_val, end_val} =
      case assigns.filter.value do
        {s, e} -> {s, e}
        _ -> {nil, nil}
      end

    assigns = assign(assigns, start_val: start_val, end_val: end_val)

    ~H"""
    <div class="flex items-center gap-1">
      <input
        type="date"
        class="input input-bordered input-sm"
        value={@start_val || ""}
        phx-change="change_date_range"
        phx-value-id={@filter.id}
        phx-value-end={@end_val || ""}
        phx-target={@myself}
        name={"filter[#{@filter.id}][start]"}
      />
      <span class="text-sm text-base-content/50">to</span>
      <input
        type="date"
        class="input input-bordered input-sm"
        value={@end_val || ""}
        phx-change="change_date_range"
        phx-value-id={@filter.id}
        phx-value-start={@start_val || ""}
        phx-target={@myself}
        name={"filter[#{@filter.id}][end]"}
      />
    </div>
    """
  end
end
