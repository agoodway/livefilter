defmodule LiveFilter.TestLive do
  use Phoenix.LiveView

  @configs [
    LiveFilter.text(:search, label: "Search", always_on: true),
    LiveFilter.select(:status, label: "Status", options: ~w(pending active shipped)),
    LiveFilter.boolean(:urgent, label: "Urgent"),
    LiveFilter.boolean(:active,
      label: "Active",
      nullable: true,
      true_label: "Active",
      false_label: "Inactive",
      any_label: "All"
    ),
    LiveFilter.date_range(:created_at, label: "Created"),
    LiveFilter.datetime(:updated_at, label: "Updated", time_format: :twelve_hour),
    LiveFilter.datetime(:due_at, label: "Due", time_format: :twenty_four_hour, minute_step: 15),
    LiveFilter.radio_group(:priority, label: "Priority", options: ~w(low medium high)),
    LiveFilter.radio_group(:category,
      label: "Category",
      options: ~w(feature bug support docs other),
      style: :radios
    )
  ]

  def configs, do: @configs

  @impl true
  def mount(_params, _session, socket) do
    initial_filters =
      @configs
      |> Enum.filter(& &1.always_on)
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
