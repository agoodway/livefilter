defmodule LiveFilter.QueryBuilderTest do
  use ExUnit.Case

  alias LiveFilter.{Filter, QueryBuilder}

  # A minimal "schema" for testing Ecto queries
  defmodule Task do
    use Ecto.Schema

    schema "tasks" do
      field(:title, :string)
      field(:status, :string)
      field(:priority, :string)
      field(:urgent, :boolean)
      field(:due_date, :date)
      field(:estimated_hours, :integer)
      field(:tags, {:array, :string})
    end
  end

  @configs [
    LiveFilter.text(:title, label: "Title"),
    LiveFilter.select(:status, label: "Status", options: ~w(pending active)),
    LiveFilter.number(:estimated_hours, label: "Hours"),
    LiveFilter.date_range(:due_date, label: "Due Date"),
    LiveFilter.boolean(:urgent, label: "Urgent"),
    LiveFilter.multi_select(:tags, label: "Tags", options: ~w(urgent bug))
  ]

  defp make_filter(field, type, operator, value, opts \\ []) do
    config = Kernel.apply(LiveFilter, type, [field, opts])
    Filter.new(config, operator, value)
  end

  describe "apply/3 with filter list" do
    test "applies eq filter to query" do
      filter = make_filter(:status, :select, :eq, "active", options: ~w(active))
      query = QueryBuilder.apply(Task, [filter])
      assert %Ecto.Query{} = query
      assert inspect(query) =~ "status"
    end

    test "applies multiple filters" do
      filters = [
        make_filter(:status, :select, :eq, "active", options: ~w(active)),
        make_filter(:urgent, :boolean, :is, true)
      ]

      query = QueryBuilder.apply(Task, filters)
      query_str = inspect(query)
      assert query_str =~ "status"
      assert query_str =~ "urgent"
    end

    test "decomposes date_range gte_lte into two filters" do
      filter = make_filter(:due_date, :date_range, :gte_lte, {~D[2024-01-01], ~D[2024-02-01]})
      query = QueryBuilder.apply(Task, [filter])
      query_str = inspect(query)
      assert query_str =~ "due_date"
    end

    test "date_range with only start value" do
      filter = make_filter(:due_date, :date_range, :gte_lte, {~D[2024-01-01], nil})
      query = QueryBuilder.apply(Task, [filter])
      assert %Ecto.Query{} = query
    end

    test "allowed_fields filters out non-allowed fields" do
      filters = [
        make_filter(:status, :select, :eq, "active", options: ~w(active)),
        make_filter(:urgent, :boolean, :is, true)
      ]

      query = QueryBuilder.apply(Task, filters, allowed_fields: [:status])
      query_str = inspect(query)
      assert query_str =~ "status"
      refute query_str =~ "urgent"
    end

    test "empty filter list returns unchanged query" do
      query = QueryBuilder.apply(Task, [])
      # Should just return the base queryable
      assert query == Task
    end

    test "applies select :in filter" do
      filter =
        make_filter(:status, :select, :in, ["active", "pending"],
          options: ~w(active pending shipped),
          operators: [:eq, :neq, :in, :not_in]
        )

      query = QueryBuilder.apply(Task, [filter])
      assert %Ecto.Query{} = query
      query_str = inspect(query)
      assert query_str =~ "status"
      assert query_str =~ "in"
    end

    test "applies select :not_in filter" do
      filter =
        make_filter(:status, :select, :not_in, ["draft"],
          options: ~w(draft active shipped),
          operators: [:eq, :neq, :in, :not_in]
        )

      query = QueryBuilder.apply(Task, [filter])
      assert %Ecto.Query{} = query
      query_str = inspect(query)
      assert query_str =~ "status"
      assert query_str =~ "not in"
    end

    test "applies select :not_in filter with multiple values" do
      filter =
        make_filter(:status, :select, :not_in, ["draft", "cancelled"],
          options: ~w(draft active shipped cancelled),
          operators: [:eq, :neq, :in, :not_in]
        )

      query = QueryBuilder.apply(Task, [filter])
      assert %Ecto.Query{} = query
      query_str = inspect(query)
      assert query_str =~ "status"
    end

    test "applies combined :in and :not_in filters on different fields" do
      filters = [
        make_filter(:status, :select, :in, ["active", "pending"],
          options: ~w(active pending shipped),
          operators: [:eq, :neq, :in, :not_in]
        ),
        make_filter(:priority, :select, :not_in, ["low"],
          options: ~w(low medium high),
          operators: [:eq, :neq, :in, :not_in]
        )
      ]

      query = QueryBuilder.apply(Task, filters)
      assert %Ecto.Query{} = query
      query_str = inspect(query)
      assert query_str =~ "status"
      assert query_str =~ "priority"
    end
  end

  describe "apply/3 with param map" do
    test "parses and applies param map" do
      params = %{"status" => "eq.active"}
      query = QueryBuilder.apply(Task, params, config: @configs)
      assert %Ecto.Query{} = query
      assert inspect(query) =~ "status"
    end
  end

  describe "apply/3 with schema type casting" do
    test "casts string values to schema types" do
      filter = make_filter(:estimated_hours, :number, :gt, "10")
      query = QueryBuilder.apply(Task, [filter], schema: Task)
      assert %Ecto.Query{} = query
    end
  end

  describe "apply_raw/3" do
    test "parses raw param map and applies" do
      params = %{"status" => "eq.active"}
      query = QueryBuilder.apply_raw(Task, params)
      assert %Ecto.Query{} = query
      assert inspect(query) =~ "status"
    end

    test "skips invalid operator values" do
      params = %{"status" => "eq.active", "bad" => "not_valid"}
      query = QueryBuilder.apply_raw(Task, params)
      assert %Ecto.Query{} = query
    end

    test "respects allowed_fields" do
      params = %{"status" => "eq.active", "urgent" => "is.true"}
      query = QueryBuilder.apply_raw(Task, params, allowed_fields: [:status])
      query_str = inspect(query)
      assert query_str =~ "status"
      refute query_str =~ "urgent"
    end
  end
end
