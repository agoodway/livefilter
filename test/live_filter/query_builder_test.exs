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

  describe "apply/3 query shape" do
    defp where_params(query) do
      Enum.flat_map(query.wheres, fn %{params: params} -> Enum.map(params, &elem(&1, 0)) end)
    end

    defp where_sql(query),
      do: query |> Inspect.Ecto.Query.to_string() |> String.replace("\n", " ")

    test "ilike wraps the value in % for substring matching" do
      query = QueryBuilder.apply(Task, [make_filter(:title, :text, :ilike, "foo")])
      assert where_sql(query) =~ ~s|ilike(t0.title, ^"%foo%")|
    end

    test "like wraps the value in % too" do
      query = QueryBuilder.apply(Task, [make_filter(:title, :text, :like, "foo")])
      assert where_sql(query) =~ ~s|like(t0.title, ^"%foo%")|
    end

    test "date range bounds become gte and lte" do
      filter = make_filter(:due_date, :date_range, :gte_lte, {~D[2024-01-01], ~D[2024-02-01]})
      query = QueryBuilder.apply(Task, [filter])
      assert where_sql(query) =~ "t0.due_date >= ^~D[2024-01-01]"
      assert where_sql(query) =~ "t0.due_date <= ^~D[2024-02-01]"
    end

    test "boolean is compiles to IS TRUE" do
      query = QueryBuilder.apply(Task, [make_filter(:urgent, :boolean, :is, true)])
      assert where_sql(query) =~ ~s|fragment("? IS TRUE", t0.urgent)|
    end

    test "is_null compiles to is_nil" do
      query = QueryBuilder.apply(Task, [make_filter(:title, :text, :is_null, true)])
      assert where_sql(query) =~ "is_nil(t0.title)"

      query = QueryBuilder.apply(Task, [make_filter(:title, :text, :is_null, false)])
      assert where_sql(query) =~ "not is_nil(t0.title)"
    end

    test "multi_select ov and cs compile to array operators" do
      query =
        QueryBuilder.apply(Task, [
          make_filter(:tags, :multi_select, :ov, ["bug"], options: ~w(a b bug))
        ])

      assert where_sql(query) =~ ~s|fragment("? && ?", t0.tags, ^["bug"])|

      query =
        QueryBuilder.apply(Task, [
          make_filter(:tags, :multi_select, :cs, ["a", "b"], options: ~w(a b bug))
        ])

      assert where_sql(query) =~ ~s|fragment("? @> ?", t0.tags, ^["a", "b"])|
    end

    test "not_in compiles to not in" do
      filter = make_filter(:status, :select, :not_in, ["draft"], options: ~w(draft))
      assert where_sql(QueryBuilder.apply(Task, [filter])) =~ ~s|t0.status not in ^["draft"]|
    end

    test ":schema casts string values to the field types" do
      filters = [
        make_filter(:estimated_hours, :number, :gt, "10"),
        make_filter(:due_date, :date, :eq, "2024-01-15"),
        make_filter(:urgent, :boolean, :eq, "true")
      ]

      query = QueryBuilder.apply(Task, filters, schema: Task)
      assert where_params(query) == [10, ~D[2024-01-15], true]
    end

    test "without :schema values are left for Ecto to cast" do
      query = QueryBuilder.apply(Task, [make_filter(:estimated_hours, :number, :gt, "10")])
      assert where_params(query) == ["10"]
    end
  end

  describe "filters that cannot be applied" do
    setup do
      %{
        bad_value: make_filter(:estimated_hours, :number, :gt, "lots"),
        unknown_field: make_filter(:owner, :text, :eq, "ann"),
        good: make_filter(:status, :select, :eq, "active", options: ~w(active))
      }
    end

    test "apply/3 skips them and applies the rest", ctx do
      filters = [ctx.bad_value, ctx.good, ctx.unknown_field]
      query = QueryBuilder.apply(Task, filters, schema: Task)

      assert [%{params: [{"active", _type}]}] = query.wheres
    end

    test "apply/3 with only rejected filters leaves the query unfiltered", ctx do
      assert QueryBuilder.apply(Task, [ctx.bad_value], schema: Task) == Task
    end

    test "apply_with_errors/3 returns the skipped filters with their errors in order", ctx do
      filters = [ctx.bad_value, ctx.good, ctx.unknown_field]

      assert {query,
              [
                {%Filter{field: :estimated_hours}, %PgRest.Error{code: "22P02"}},
                {%Filter{field: :owner}, %PgRest.Error{code: "42703"}}
              ]} = QueryBuilder.apply_with_errors(Task, filters, schema: Task)

      assert [%{params: [{"active", _type}]}] = query.wheres
    end

    test "apply_with_errors/3 has no errors when every filter applies", ctx do
      assert {%Ecto.Query{}, []} = QueryBuilder.apply_with_errors(Task, [ctx.good], schema: Task)
    end

    test "apply_with_errors/3 takes a param map with :config" do
      params = %{"estimated_hours" => "gt.lots", "status" => "eq.active"}

      assert {query, [{%Filter{field: :estimated_hours}, %PgRest.Error{code: "22P02"}}]} =
               QueryBuilder.apply_with_errors(Task, params, config: @configs, schema: Task)

      assert [%{params: [{"active", _type}]}] = query.wheres
    end

    test "apply_with_errors/3 skips and reports a param the grammar rejects" do
      params = %{"urgent" => "is.maybe", "status" => "eq.active"}

      assert {query, [{%Filter{field: :urgent}, %PgRest.Error{code: "PGRST100"}}]} =
               QueryBuilder.apply_with_errors(Task, params, config: @configs, schema: Task)

      assert [%{params: [{"active", _type}]}] = query.wheres
    end

    test "apply_with_errors/3 does not report a rejected param outside :allowed_fields" do
      params = %{"urgent" => "is.maybe"}

      assert {Task, []} =
               QueryBuilder.apply_with_errors(Task, params,
                 config: @configs,
                 schema: Task,
                 allowed_fields: [:status]
               )
    end

    test "a date range with one bad bound is skipped as a whole" do
      filter = make_filter(:due_date, :date_range, :gte_lte, {"2024-01-01", "soon"})

      assert {query, [{%Filter{field: :due_date}, %PgRest.Error{code: "22P02"}}]} =
               QueryBuilder.apply_with_errors(Task, [filter], schema: Task)

      assert query == Task
    end

    test "apply!/3 raises the first error", ctx do
      assert_raise PgRest.Error, ~r/estimated_hours/, fn ->
        QueryBuilder.apply!(Task, [ctx.good, ctx.bad_value], schema: Task)
      end
    end

    test "apply!/3 returns the query when every filter applies", ctx do
      assert [%{params: [{"active", _type}]}] =
               QueryBuilder.apply!(Task, [ctx.good], schema: Task).wheres
    end

    test "apply_raw/3 skips an uncastable value or unknown field" do
      params = %{"estimated_hours" => "gt.lots", "owner" => "eq.ann", "status" => "eq.active"}
      query = QueryBuilder.apply_raw(Task, params)

      assert [%{params: [{"active", _type}]}] = query.wheres
    end

    test "apply_raw!/3 raises instead" do
      assert_raise PgRest.Error, ~r/estimated_hours/, fn ->
        QueryBuilder.apply_raw!(Task, %{"estimated_hours" => "gt.lots"})
      end

      assert_raise PgRest.Error, ~r/owner/, fn ->
        QueryBuilder.apply_raw!(Task, %{"owner" => "eq.ann"})
      end
    end

    test "a schemaless apply_raw without :allowed_fields is still an ArgumentError" do
      assert_raise ArgumentError, fn ->
        QueryBuilder.apply_raw("tasks", %{"status" => "eq.active"})
      end
    end
  end

  describe "apply/3 with uuid and enum schema fields" do
    defmodule Ticket do
      use Ecto.Schema

      @primary_key {:id, :binary_id, autogenerate: false}
      schema "tickets" do
        field(:owner_id, Ecto.UUID)
        field(:state, Ecto.Enum, values: [:open, :closed])
      end
    end

    test "casts uuids and enum values" do
      uuid = "6f8e1f3c-2b9a-4d7e-9c1a-0b2d3e4f5a6b"

      filters = [
        make_filter(:owner_id, :select, :eq, uuid, options: [uuid]),
        make_filter(:state, :select, :in, ["open"], options: ~w(open closed))
      ]

      query = QueryBuilder.apply(Ticket, filters, schema: Ticket)
      assert where_params(query) == [uuid, [:open]]
    end
  end

  describe "apply_raw/3 operators and casting" do
    test "casts with the query's schema and applies negations" do
      query = QueryBuilder.apply_raw(Task, %{"estimated_hours" => "not.gt.10"})
      assert where_sql(query) =~ "not (t0.estimated_hours > ^10)"
      assert where_params(query) == [10]
    end

    test "in and is" do
      query = QueryBuilder.apply_raw(Task, %{"status" => "in.(a,b)", "title" => "is.null"})
      sql = where_sql(query)
      assert sql =~ ~s|t0.status in ^["a", "b"]|
      assert sql =~ "is_nil(t0.title)"
    end

    test "a schemaless source filters only :allowed_fields" do
      query =
        QueryBuilder.apply_raw("tasks", %{"status" => "eq.active"}, allowed_fields: [:status])

      assert where_sql(query) =~ ~s|t0.status == ^"active"|
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

defmodule LiveFilter.QueryBuilder.ApplySortTest do
  use ExUnit.Case, async: true
  alias LiveFilter.QueryBuilder
  alias LiveFilter.Sort
  alias LiveFilter.Sort.Entry

  defp order_bys(%Ecto.Query{order_bys: obs}) do
    Enum.flat_map(obs, fn ob ->
      Enum.map(ob.expr, fn {dir, {{:., _, [_, field]}, _, _}} -> {dir, field} end)
    end)
  end

  test "maps a single entry to order_by using query_field, then appends the :id tiebreaker" do
    sort = %Sort{entries: [%Entry{field: :clicks, direction: :desc, query_field: :total_clicks}]}
    query = QueryBuilder.apply_sort("links", sort)
    assert order_bys(query) == [desc: :total_clicks, asc: :id]
  end

  test "falls back to the public field when query_field is nil" do
    sort = %Sort{entries: [%Entry{field: :name, direction: :asc}]}
    assert order_bys(QueryBuilder.apply_sort("links", sort)) == [asc: :name, asc: :id]
  end

  test "maps nulls placement to the nulls-aware ecto direction" do
    sort = %Sort{
      entries: [
        %Entry{field: :clicks, direction: :desc, query_field: :total_clicks, nulls: :last}
      ]
    }

    assert order_bys(QueryBuilder.apply_sort("links", sort)) == [
             desc_nulls_last: :total_clicks,
             asc: :id
           ]
  end

  test "preserves multi-entry order then tiebreaker" do
    sort = %Sort{
      entries: [
        %Entry{field: :clicks, direction: :desc, query_field: :total_clicks},
        %Entry{field: :created, direction: :asc, query_field: :inserted_at}
      ]
    }

    assert order_bys(QueryBuilder.apply_sort("links", sort)) ==
             [desc: :total_clicks, asc: :inserted_at, asc: :id]
  end

  test "empty sort applies only the tiebreaker" do
    assert order_bys(QueryBuilder.apply_sort("links", %Sort{})) == [asc: :id]
  end

  test "does not duplicate the tiebreaker if already sorted by it" do
    sort = %Sort{entries: [%Entry{field: :id, direction: :desc, query_field: :id}]}
    assert order_bys(QueryBuilder.apply_sort("links", sort)) == [desc: :id]
  end

  test "tiebreak: false disables the tiebreaker" do
    sort = %Sort{entries: [%Entry{field: :clicks, direction: :desc, query_field: :total_clicks}]}

    assert order_bys(QueryBuilder.apply_sort("links", sort, tiebreak: false)) == [
             desc: :total_clicks
           ]
  end

  test "tiebreak can be a custom field" do
    assert order_bys(QueryBuilder.apply_sort("links", %Sort{}, tiebreak: :uuid)) == [asc: :uuid]
  end
end
