defmodule LiveFilter.IntegrationTest do
  use ExUnit.Case

  alias LiveFilter.Filter

  @configs [
    LiveFilter.text(:name, label: "Name"),
    LiveFilter.select(:status, label: "Status", options: ~w(pending active shipped)),
    LiveFilter.boolean(:urgent, label: "Urgent")
  ]

  describe "init/3" do
    test "assigns live_filter with config and empty filters" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
      socket = LiveFilter.init(socket, @configs)

      assert %{config: config, filters: [], id: id} = socket.assigns.live_filter
      assert config == @configs
      assert String.starts_with?(id, "live-filter-")
    end

    test "assigns live_filter with provided filters" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
      config = Enum.find(@configs, &(&1.field == :status))
      filters = [Filter.new(config, :eq, "active")]

      socket = LiveFilter.init(socket, @configs, filters)
      assert [%Filter{field: :status, value: "active"}] = socket.assigns.live_filter.filters
    end

    test "generates unique IDs across calls" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
      s1 = LiveFilter.init(socket, @configs)
      s2 = LiveFilter.init(socket, @configs)
      assert s1.assigns.live_filter.id != s2.assigns.live_filter.id
    end
  end

  describe "from_params/2" do
    test "parses URL params into filters and remaining" do
      params = %{"status" => "eq.active", "page" => "2"}
      {filters, remaining} = LiveFilter.from_params(params, @configs)

      assert [%Filter{field: :status, operator: :eq, value: "active"}] = filters
      assert remaining == %{"page" => "2"}
    end

    test "returns empty filters for no matching params" do
      {filters, remaining} = LiveFilter.from_params(%{"page" => "1"}, @configs)
      assert filters == []
      assert remaining == %{"page" => "1"}
    end
  end
end
