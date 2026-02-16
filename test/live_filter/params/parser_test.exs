defmodule LiveFilter.Params.ParserTest do
  use ExUnit.Case

  alias LiveFilter.Filter
  alias LiveFilter.Params.Parser

  @configs [
    LiveFilter.text(:name, label: "Name"),
    LiveFilter.select(:status, label: "Status", options: ~w(pending active shipped)),
    LiveFilter.multi_select(:tags, label: "Tags", options: ~w(urgent bug feature)),
    LiveFilter.number(:amount, label: "Amount"),
    LiveFilter.date(:due_date, label: "Due Date"),
    LiveFilter.date_range(:inserted_at, label: "Created"),
    LiveFilter.datetime_range(:started_at, label: "Started"),
    LiveFilter.boolean(:urgent, label: "Urgent"),
    LiveFilter.text(:title, label: "Title", custom_param: "search")
  ]

  describe "from_params/2" do
    test "parses simple eq filter" do
      {filters, remaining} = Parser.from_params(%{"status" => "eq.active"}, @configs)
      assert remaining == %{}
      assert [%Filter{field: :status, operator: :eq, value: "active"}] = filters
    end

    test "parses ilike filter and strips wildcards" do
      {filters, _} = Parser.from_params(%{"name" => "ilike.*foo*"}, @configs)
      # Parser strips wildcards since they're re-added during serialization
      assert [%Filter{field: :name, operator: :ilike, value: "foo"}] = filters
    end

    test "parses IN filter" do
      {filters, _} = Parser.from_params(%{"tags" => "in.(urgent,bug)"}, @configs)
      assert [%Filter{field: :tags, operator: :in, value: ["urgent", "bug"]}] = filters
    end

    test "parses select :in filter with multiple values" do
      configs = [
        LiveFilter.select(:status,
          label: "Status",
          options: ~w(pending active shipped),
          operators: [:eq, :neq, :in, :not_in]
        )
      ]

      {filters, _} = Parser.from_params(%{"status" => "in.(active,pending)"}, configs)

      assert [%Filter{field: :status, operator: :in, value: ["active", "pending"]}] = filters
    end

    test "parses select :not_in filter" do
      configs = [
        LiveFilter.select(:status,
          label: "Status",
          options: ~w(draft active shipped),
          operators: [:eq, :neq, :in, :not_in]
        )
      ]

      {filters, _} = Parser.from_params(%{"status" => "not_in.(draft)"}, configs)
      assert [%Filter{field: :status, operator: :not_in, value: ["draft"]}] = filters
    end

    test "parses select :not_in filter with multiple values" do
      configs = [
        LiveFilter.select(:status,
          label: "Status",
          options: ~w(draft active shipped cancelled),
          operators: [:eq, :neq, :in, :not_in]
        )
      ]

      {filters, _} = Parser.from_params(%{"status" => "not_in.(draft,cancelled)"}, configs)

      assert [%Filter{field: :status, operator: :not_in, value: ["draft", "cancelled"]}] = filters
    end

    test "parses boolean filter" do
      {filters, _} = Parser.from_params(%{"urgent" => "is.true"}, @configs)
      assert [%Filter{field: :urgent, operator: :is, value: true}] = filters
    end

    test "parses number comparison" do
      {filters, _} = Parser.from_params(%{"amount" => "gt.100"}, @configs)
      assert [%Filter{field: :amount, operator: :gt, value: "100"}] = filters
    end

    test "parses date eq filter" do
      {filters, _} = Parser.from_params(%{"due_date" => "eq.2026-02-15"}, @configs)
      assert [%Filter{field: :due_date, operator: :eq, value: "2026-02-15"}] = filters
    end

    test "parses date comparison operators" do
      {filters, _} = Parser.from_params(%{"due_date" => "gte.2026-01-01"}, @configs)
      assert [%Filter{field: :due_date, operator: :gte, value: "2026-01-01"}] = filters

      {filters, _} = Parser.from_params(%{"due_date" => "lt.2026-03-01"}, @configs)
      assert [%Filter{field: :due_date, operator: :lt, value: "2026-03-01"}] = filters
    end

    test "merges date range gte/lte into single filter" do
      params = %{"inserted_at" => ["gte.2024-01-01", "lte.2024-02-01"]}
      {filters, _} = Parser.from_params(params, @configs)

      assert [
               %Filter{
                 field: :inserted_at,
                 operator: :gte_lte,
                 value: {"2024-01-01", "2024-02-01"}
               }
             ] = filters
    end

    test "matches custom_param key and strips wildcards" do
      {filters, _} = Parser.from_params(%{"search" => "ilike.*test*"}, @configs)
      # Parser strips wildcards since they're re-added during serialization
      assert [%Filter{field: :title, operator: :ilike, value: "test"}] = filters
    end

    test "custom param without operator prefix uses default operator" do
      {filters, _} = Parser.from_params(%{"search" => "hello"}, @configs)
      assert [%Filter{field: :title, operator: :ilike, value: "hello"}] = filters
    end

    test "unrecognized params are returned as remaining" do
      {filters, remaining} =
        Parser.from_params(%{"status" => "eq.active", "page" => "2", "limit" => "25"}, @configs)

      assert [%Filter{field: :status}] = filters
      assert remaining == %{"page" => "2", "limit" => "25"}
    end

    test "returns empty filters for empty params" do
      {filters, remaining} = Parser.from_params(%{}, @configs)
      assert filters == []
      assert remaining == %{}
    end

    test "parses multiple filters" do
      params = %{"status" => "eq.active", "urgent" => "is.true"}
      {filters, _} = Parser.from_params(params, @configs)
      assert length(filters) == 2
      fields = Enum.map(filters, & &1.field) |> Enum.sort()
      assert fields == [:status, :urgent]
    end

    test "merges datetime_range gte/lte into single filter" do
      params = %{"started_at" => ["gte.2026-01-17T00:00:00Z", "lte.2026-02-15T23:59:59Z"]}
      {filters, _} = Parser.from_params(params, @configs)

      assert [
               %Filter{
                 field: :started_at,
                 operator: :gte_lte,
                 value: {"2026-01-17T00:00:00Z", "2026-02-15T23:59:59Z"}
               }
             ] = filters
    end

    test "parses datetime_range from and param" do
      params = %{
        "and" => "(started_at.gte.2026-01-17T00:00:00Z,started_at.lte.2026-02-15T23:59:59Z)"
      }

      {filters, remaining} = Parser.from_params(params, @configs)

      assert [
               %Filter{
                 field: :started_at,
                 operator: :gte_lte,
                 value: {"2026-01-17T00:00:00Z", "2026-02-15T23:59:59Z"}
               }
             ] = filters

      assert remaining == %{}
    end

    test "datetime_range preserves full ISO8601 timestamps" do
      params = %{"started_at" => ["gte.2026-02-15T00:00:00Z", "lte.2026-02-15T23:59:59Z"]}
      {filters, _} = Parser.from_params(params, @configs)

      assert [%Filter{value: {start_val, end_val}}] = filters
      assert start_val == "2026-02-15T00:00:00Z"
      assert end_val == "2026-02-15T23:59:59Z"
    end
  end
end
