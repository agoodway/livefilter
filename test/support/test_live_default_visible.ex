defmodule LiveFilter.TestLiveDefaultVisible do
  @moduledoc """
  Test LiveView that includes default_visible filters for testing clear_all behavior.
  """
  use Phoenix.LiveView

  @configs [
    LiveFilter.text(:search, label: "Search", always_on: true),
    LiveFilter.select(:status,
      label: "Status",
      options: ~w(pending active shipped),
      default_visible: true
    ),
    LiveFilter.boolean(:urgent, label: "Urgent", default_visible: true),
    LiveFilter.boolean(:active,
      label: "Active",
      nullable: true,
      true_label: "Active",
      false_label: "Inactive",
      any_label: "All"
    ),
    LiveFilter.date_range(:created_at, label: "Created"),
    LiveFilter.radio_group(:priority, label: "Priority", options: ~w(low medium high))
  ]

  def configs, do: @configs

  @impl true
  def mount(_params, _session, socket) do
    # Initialize with always_on and default_visible filters
    initial_filters =
      @configs
      |> Enum.filter(fn c -> c.always_on or c.default_visible end)
      |> Enum.map(&LiveFilter.Filter.new/1)

    socket =
      socket
      |> LiveFilter.init(@configs, initial_filters)
      |> assign(:updated_params, nil)

    {:ok, socket}
  end

  @impl true
  def handle_info({:live_filter, :updated, params}, socket) do
    {:noreply, assign(socket, :updated_params, params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LiveFilter.bar filter={@live_filter} />
    <div id="updated-params">{inspect(@updated_params)}</div>
    """
  end
end
