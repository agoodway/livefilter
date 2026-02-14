defmodule LiveFilter.Params.RoundTripTest do
  use ExUnit.Case

  alias LiveFilter.Filter
  alias LiveFilter.Params.{Parser, Serializer}

  @configs [
    LiveFilter.text(:name, label: "Name"),
    LiveFilter.select(:status, label: "Status", options: ~w(pending active shipped)),
    LiveFilter.multi_select(:tags, label: "Tags", options: ~w(urgent bug feature)),
    LiveFilter.number(:amount, label: "Amount"),
    LiveFilter.date_range(:inserted_at, label: "Created"),
    LiveFilter.boolean(:urgent, label: "Urgent")
  ]

  describe "round-trip: serialize -> parse -> serialize" do
    test "eq filter round-trips" do
      config = Enum.find(@configs, &(&1.field == :status))
      original = [Filter.new(config, :eq, "active")]

      params = Serializer.to_params(original)
      {parsed, _} = Parser.from_params(params, @configs)
      re_params = Serializer.to_params(parsed)

      assert params == re_params
    end

    test "boolean filter round-trips" do
      config = Enum.find(@configs, &(&1.field == :urgent))
      original = [Filter.new(config, :is, true)]

      params = Serializer.to_params(original)
      {parsed, _} = Parser.from_params(params, @configs)
      re_params = Serializer.to_params(parsed)

      assert params == re_params
    end

    test "IN filter round-trips" do
      config = Enum.find(@configs, &(&1.field == :tags))
      original = [Filter.new(config, :in, ["urgent", "bug"])]

      params = Serializer.to_params(original)
      {parsed, _} = Parser.from_params(params, @configs)
      re_params = Serializer.to_params(parsed)

      assert params == re_params
    end

    test "date range filter round-trips" do
      config = Enum.find(@configs, &(&1.field == :inserted_at))
      original = [Filter.new(config, :gte_lte, {"2024-01-01", "2024-02-01"})]

      params = Serializer.to_params(original)
      {parsed, _} = Parser.from_params(params, @configs)
      re_params = Serializer.to_params(parsed)

      assert params == re_params
    end

    test "ilike filter round-trips" do
      config = Enum.find(@configs, &(&1.field == :name))
      original = [Filter.new(config, :ilike, "*foo*")]

      params = Serializer.to_params(original)
      {parsed, _} = Parser.from_params(params, @configs)
      re_params = Serializer.to_params(parsed)

      assert params == re_params
    end

    test "multiple filters round-trip" do
      status_config = Enum.find(@configs, &(&1.field == :status))
      urgent_config = Enum.find(@configs, &(&1.field == :urgent))

      original = [
        Filter.new(status_config, :eq, "active"),
        Filter.new(urgent_config, :is, true)
      ]

      params = Serializer.to_params(original)
      {parsed, _} = Parser.from_params(params, @configs)
      re_params = Serializer.to_params(parsed)

      assert params == re_params
    end
  end
end
