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

  describe "init/4 with context" do
    test "stores context in live_filter assign" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
      context = %{board_id: "abc-123"}
      socket = LiveFilter.init(socket, @configs, [], context: context)

      assert socket.assigns.live_filter.context == %{board_id: "abc-123"}
    end

    test "defaults context to empty map when not provided" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
      socket = LiveFilter.init(socket, @configs)

      assert socket.assigns.live_filter.context == %{}
    end

    test "preserves existing ID when context is provided" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
      socket = LiveFilter.init(socket, @configs, [], context: %{board_id: "abc"})
      id = socket.assigns.live_filter.id

      socket = LiveFilter.init(socket, @configs, [], context: %{board_id: "abc"})
      assert socket.assigns.live_filter.id == id
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
