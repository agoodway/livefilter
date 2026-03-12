defmodule LiveFilter.TestLiveAsyncSelect do
  use Phoenix.LiveView

  @base_configs [
    LiveFilter.text(:search, label: "Search", always_on: true),
    LiveFilter.select(:status, label: "Status", options: ~w(pending active shipped))
  ]

  @impl true
  def mount(_params, _session, socket) do
    configs =
      @base_configs ++
        [
          LiveFilter.async_select(:company_id,
            label: "Employer",
            search_fn: &search_companies/2,
            load_label_fn: &load_company_name/2,
            min_chars: 2,
            debounce: 100
          )
        ]

    initial_filters =
      configs
      |> Enum.filter(& &1.always_on)
      |> Enum.map(&LiveFilter.Filter.new/1)

    socket =
      socket
      |> LiveFilter.init(configs, initial_filters, context: %{board_id: "test-board"})
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

  defp search_companies(query, _context) do
    companies = [
      {"c1", "Acme Corp"},
      {"c2", "Acme Industries"},
      {"c3", "Beta LLC"},
      {"c4", "Gamma Inc"}
    ]

    query_lower = String.downcase(query)

    Enum.filter(companies, fn {_id, name} ->
      String.contains?(String.downcase(name), query_lower)
    end)
  end

  defp load_company_name(value, _context) do
    labels = %{
      "c1" => "Acme Corp",
      "c2" => "Acme Industries",
      "c3" => "Beta LLC",
      "c4" => "Gamma Inc"
    }

    case Map.get(labels, value) do
      nil -> :error
      label -> {:ok, label}
    end
  end
end
