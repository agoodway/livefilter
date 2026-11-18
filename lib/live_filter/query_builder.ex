defmodule LiveFilter.QueryBuilder do
  @moduledoc """
  Thin query builder that converts LiveFilter structs to PgRest filter AST nodes
  (`PgRest.AST.Condition`) and applies them with `PgRest.Ecto.Filter.where/3`.
  """

  import Kernel, except: [apply: 3]
  import Ecto.Query, only: [limit: 2, offset: 2, exclude: 2, order_by: 3]

  alias LiveFilter.{Filter, Pagination, Sort}
  alias LiveFilter.Params.Parser
  alias PgRest.AST.{Condition, Field}
  alias PgRest.Ecto.Filter, as: EctoFilter
  alias PgRest.Error
  alias PgRest.Grammar.Filter, as: Grammar

  @typedoc "A filter that could not be applied, with the reason."
  @type rejection :: {Filter.t(), Error.t()}

  @doc """
  Applies a list of Filter structs to an Ecto query.

  Converts each Filter to `PgRest.AST.Condition`s (a date range becomes a `gte` and an
  `lte`) and applies them with `PgRest.Ecto.Filter.where/3`.

  A filter that cannot be applied is skipped: with `:schema`, a value its field type
  rejects (`22P02`, e.g. `?qty=gt.lots` typed into the URL) or a field that is not a
  schema field (`42703`); in a param map, a value the PostgREST grammar rejects
  (`PGRST100`, e.g. `?enabled=is.maybe`). The other filters still apply, so a
  hand-edited URL never crashes the LiveView. Use `apply_with_errors/3` to report the skipped filters, or
  `apply!/3` to raise.

  ## Options

    * `:schema` - Ecto schema module; values are cast to its field types
    * `:allowed_fields` - list of atoms restricting which fields can be filtered
    * `:config` - filter config list (required when passing a param map instead of filters)
  """
  @spec apply(Ecto.Queryable.t(), [Filter.t()] | map(), keyword()) :: Ecto.Queryable.t()
  def apply(query, filters_or_params, opts \\ []) do
    {query, _rejected} = apply_with_errors(query, filters_or_params, opts)
    query
  end

  @doc """
  Like `apply/3`, but raises the first `PgRest.Error` instead of skipping the filter.
  """
  @spec apply!(Ecto.Queryable.t(), [Filter.t()] | map(), keyword()) :: Ecto.Queryable.t()
  def apply!(query, filters_or_params, opts \\ []) do
    query
    |> apply_with_errors(filters_or_params, opts)
    |> raise_first()
  end

  @doc """
  Like `apply/3`, and also returns the skipped filters with their `PgRest.Error`, in
  filter order, e.g. to flash which URL filters were ignored.
  """
  @spec apply_with_errors(Ecto.Queryable.t(), [Filter.t()] | map(), keyword()) ::
          {Ecto.Queryable.t(), [rejection()]}
  def apply_with_errors(query, filters_or_params, opts \\ [])

  def apply_with_errors(query, %{} = params, opts) do
    {configs, opts} = Keyword.pop!(opts, :config)
    {filters, _remaining, unparsed} = Parser.from_params_with_errors(params, configs)
    {query, rejected} = apply_with_errors(query, filters, opts)
    {query, allowed_rejections(unparsed, Keyword.get(opts, :allowed_fields)) ++ rejected}
  end

  def apply_with_errors(query, filters, opts) when is_list(filters) do
    valid_filters =
      filters
      |> maybe_filter_allowed(Keyword.get(opts, :allowed_fields))
      |> Enum.reject(&empty_value?/1)

    filter_opts = [
      schema: Keyword.get(opts, :schema),
      fields: valid_filters |> Enum.map(& &1.field) |> Enum.uniq()
    ]

    valid_filters
    |> Enum.map(&{&1, to_conditions(&1)})
    |> where_each(query, filter_opts)
  end

  @doc """
  Applies a raw PostgREST param map to an Ecto query without filter config.

  Parses each param with `PgRest.Grammar.Filter.parse_condition/2` (params that
  are not `op.value` filters are skipped) and applies them with
  `PgRest.Ecto.Filter.where/3`. Values are cast to the query's schema fields;
  a schemaless source needs `:allowed_fields` (`ArgumentError` otherwise).

  As in `apply/3`, a param whose field is not filterable or whose value cannot be cast
  is skipped; `apply_raw!/3` raises instead.

  ## Options

    * `:schema` - Ecto schema module for type casting (defaults to the query's schema)
    * `:allowed_fields` - list of atoms restricting which fields can be filtered
  """
  @spec apply_raw(Ecto.Queryable.t(), map(), keyword()) :: Ecto.Queryable.t()
  def apply_raw(query, params, opts \\ []) when is_map(params) do
    {query, _rejected} = apply_raw_with_errors(query, params, opts)
    query
  end

  @doc """
  Like `apply_raw/3`, but raises the first `PgRest.Error` instead of skipping the param.
  """
  @spec apply_raw!(Ecto.Queryable.t(), map(), keyword()) :: Ecto.Queryable.t()
  def apply_raw!(query, params, opts \\ []) when is_map(params) do
    query
    |> apply_raw_with_errors(params, opts)
    |> raise_first()
  end

  defp apply_raw_with_errors(query, params, opts) do
    allowed_fields = Keyword.get(opts, :allowed_fields)

    filter_opts =
      opts
      |> Keyword.take([:schema])
      |> put_fields(allowed_fields)

    params
    |> Enum.flat_map(&parse_param/1)
    |> maybe_filter_allowed_conditions(allowed_fields)
    |> Enum.map(&{&1, [&1]})
    |> where_each(query, filter_opts)
  end

  defp put_fields(opts, nil), do: opts
  defp put_fields(opts, fields), do: Keyword.put(opts, :fields, fields)

  defp parse_param({key, value}) when is_binary(value) do
    case Grammar.parse_condition(key, value) do
      {:ok, condition} -> [condition]
      {:error, _error} -> []
    end
  end

  defp parse_param(_param), do: []

  # Applies each `{source, conditions}` pair on its own, so one bad filter only drops itself.
  defp where_each(entries, query, opts) do
    {query, rejected} =
      Enum.reduce(entries, {query, []}, fn {source, conditions}, {acc, rejected} ->
        case EctoFilter.where(acc, conditions, opts) do
          {:ok, acc} -> {acc, rejected}
          {:error, error} -> {acc, [{source, error} | rejected]}
        end
      end)

    {query, Enum.reverse(rejected)}
  end

  defp raise_first({query, []}), do: query
  defp raise_first({_query, [{_source, error} | _rest]}), do: raise(error)

  # Convert a Filter struct to one or more PgRest conditions
  defp to_conditions(%Filter{operator: :gte_lte, field: field, value: {start_val, end_val}}) do
    [{:gte, start_val}, {:lte, end_val}]
    |> Enum.reject(fn {_op, val} -> is_nil(val) end)
    |> Enum.map(fn {op, val} -> condition(field, op, val) end)
  end

  # ILIKE/LIKE need % wildcards for substring matching
  defp to_conditions(%Filter{field: field, operator: op, value: value})
       when op in [:ilike, :like] and is_binary(value),
       do: [condition(field, op, "%#{value}%")]

  defp to_conditions(%Filter{field: field, operator: :not_in, value: values}),
    do: [%{condition(field, :in, values) | negate: true}]

  defp to_conditions(%Filter{field: field, operator: :is_null, value: true}),
    do: [condition(field, :is, :null)]

  defp to_conditions(%Filter{field: field, operator: :is_null, value: false}),
    do: [condition(field, :is, :not_null)]

  defp to_conditions(%Filter{field: field, operator: op, value: {config, query}})
       when op in [:fts, :plfts, :phfts, :wfts],
       do: [%{condition(field, op, query) | fts_config: config}]

  defp to_conditions(%Filter{field: field, operator: op, value: value}),
    do: [condition(field, op, value)]

  defp condition(field, op, value),
    do: %Condition{field: %Field{name: Atom.to_string(field)}, op: op, value: value}

  defp maybe_filter_allowed(filters, nil), do: filters

  defp maybe_filter_allowed(filters, allowed_fields) do
    Enum.filter(filters, &(&1.field in allowed_fields))
  end

  defp allowed_rejections(rejections, nil), do: rejections

  defp allowed_rejections(rejections, allowed_fields),
    do: Enum.filter(rejections, fn {filter, _error} -> filter.field in allowed_fields end)

  defp maybe_filter_allowed_conditions(conditions, nil), do: conditions

  defp maybe_filter_allowed_conditions(conditions, allowed_fields) do
    allowed_strings = Enum.map(allowed_fields, &Atom.to_string/1)
    Enum.filter(conditions, &(&1.field.name in allowed_strings))
  end

  # Skip filters with empty/nil values (e.g., newly added always_on filters)
  defp empty_value?(%Filter{value: nil}), do: true
  defp empty_value?(%Filter{value: ""}), do: true
  defp empty_value?(%Filter{value: []}), do: true
  defp empty_value?(%Filter{operator: :gte_lte, value: {nil, nil}}), do: true
  defp empty_value?(_), do: false

  # --- Pagination ---

  @doc """
  Applies pagination (limit/offset) to an Ecto query.

  ## Example

      query
      |> LiveFilter.QueryBuilder.apply(filters, schema: Task)
      |> LiveFilter.QueryBuilder.apply_pagination(pagination)
      |> Repo.all()
  """
  @spec apply_pagination(Ecto.Queryable.t(), Pagination.t()) :: Ecto.Query.t()
  def apply_pagination(query, %Pagination{limit: lim, offset: off}) do
    query
    |> limit(^lim)
    |> offset(^off)
  end

  # --- Sort ---

  @doc """
  Applies a `LiveFilter.Sort` to an Ecto query as `order_by`, mapping each entry
  via its `query_field` and `nulls` placement.

  A deterministic tiebreaker column is appended so paginated, low-cardinality
  sorts stay stable across pages (the classic "rows skipped/repeated across
  pages" bug). Configure with `opts[:tiebreak]` (default `:id`, `false` to
  disable). For expression-based sorts, skip this and order on the parsed
  `%LiveFilter.Sort{}` yourself.

  ## Example

      query
      |> LiveFilter.QueryBuilder.apply(filters, schema: Link)
      |> LiveFilter.QueryBuilder.apply_sort(sort)        # tiebreak: :id
      |> LiveFilter.QueryBuilder.apply_pagination(pagination)
  """
  @spec apply_sort(Ecto.Queryable.t(), Sort.t(), keyword()) :: Ecto.Query.t()
  def apply_sort(query, %Sort{entries: entries}, opts \\ []) do
    tiebreak = Keyword.get(opts, :tiebreak, :id)

    specs =
      entries
      |> Enum.map(&entry_spec/1)
      |> append_tiebreak(entries, tiebreak)

    case specs do
      [] -> query
      specs -> order_by(query, [], ^specs)
    end
  end

  defp entry_spec(%Sort.Entry{direction: dir, nulls: nulls} = e) do
    {ecto_direction(dir, nulls), e.query_field || e.field}
  end

  defp ecto_direction(:asc, nil), do: :asc
  defp ecto_direction(:desc, nil), do: :desc
  defp ecto_direction(:asc, :first), do: :asc_nulls_first
  defp ecto_direction(:asc, :last), do: :asc_nulls_last
  defp ecto_direction(:desc, :first), do: :desc_nulls_first
  defp ecto_direction(:desc, :last), do: :desc_nulls_last

  defp append_tiebreak(specs, _entries, false), do: specs

  defp append_tiebreak(specs, entries, field) do
    already? = Enum.any?(entries, &((&1.query_field || &1.field) == field))
    if already?, do: specs, else: specs ++ [{:asc, field}]
  end

  @doc """
  Counts total records for a query (for pagination).

  Strips select, order_by, preload, limit, and offset to get an accurate count.

  ## Example

      base_query = Task |> LiveFilter.QueryBuilder.apply(filters, schema: Task)
      total_count = LiveFilter.QueryBuilder.count(base_query, Repo)
  """
  @spec count(Ecto.Queryable.t(), module()) :: non_neg_integer()
  def count(query, repo) do
    query
    |> exclude(:select)
    |> exclude(:order_by)
    |> exclude(:preload)
    |> exclude(:limit)
    |> exclude(:offset)
    |> repo.aggregate(:count)
  end
end
