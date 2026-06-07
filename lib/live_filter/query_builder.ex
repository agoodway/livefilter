defmodule LiveFilter.QueryBuilder do
  @moduledoc """
  Thin query builder that converts LiveFilter structs to PgRest AST maps
  and delegates to `PgRest.Filter.apply_all/2`.
  """

  import Kernel, except: [apply: 3]
  import Ecto.Query, only: [limit: 2, offset: 2, exclude: 2, where: 3, order_by: 3]

  alias LiveFilter.{Filter, Pagination, Sort}
  alias LiveFilter.Params.Parser

  @doc """
  Applies a list of Filter structs to an Ecto query.

  Converts each Filter to a PgRest-compatible AST map, splits date_range
  compound filters, optionally casts via PgRest.TypeCaster, and delegates
  to PgRest.Filter.apply_all/2.

  ## Options

    * `:schema` - Ecto schema module for type casting via `PgRest.TypeCaster.cast_filters/2`
    * `:allowed_fields` - list of atoms restricting which fields can be filtered
    * `:config` - filter config list (required when passing a param map instead of filters)
  """
  @spec apply(Ecto.Queryable.t(), [Filter.t()] | map(), keyword()) :: Ecto.Query.t()
  def apply(query, filters_or_params, opts \\ [])

  def apply(query, %{} = params, opts) do
    configs = Keyword.fetch!(opts, :config)
    {filters, _remaining} = Parser.from_params(params, configs)
    apply(query, filters, Keyword.delete(opts, :config))
  end

  def apply(query, filters, opts) when is_list(filters) do
    allowed_fields = Keyword.get(opts, :allowed_fields)
    schema = Keyword.get(opts, :schema)

    valid_filters =
      filters
      |> maybe_filter_allowed(allowed_fields)
      |> Enum.reject(&empty_value?/1)

    # Handle :not_in filters directly (PgRest's NOT wrapper has issues with complex queries)
    {not_in_filters, other_filters} = Enum.split_with(valid_filters, &(&1.operator == :not_in))
    query = apply_not_in_filters(query, not_in_filters)

    # Convert remaining filters to PgRest AST maps
    ast_maps = Enum.flat_map(other_filters, &to_ast_maps/1)
    ast_maps = maybe_cast(ast_maps, schema)

    PgRest.Filter.apply_all(query, ast_maps)
  end

  # Apply :not_in filters directly using Ecto.Query
  # This avoids PgRest's NOT wrapper which has issues with complex queries containing subqueries
  defp apply_not_in_filters(query, []), do: query

  defp apply_not_in_filters(query, filters) do
    Enum.reduce(filters, query, fn %Filter{field: field, value: values}, q ->
      where(q, [r], field(r, ^field) not in ^values)
    end)
  end

  @doc """
  Applies a raw PostgREST param map to an Ecto query without filter config.

  Parses each param via `PgRest.Parser.parse_operator_value/1` and delegates
  to `PgRest.Filter.apply_all/2`.

  ## Options

    * `:schema` - Ecto schema module for type casting
    * `:allowed_fields` - list of atoms restricting which fields can be filtered
  """
  @spec apply_raw(Ecto.Queryable.t(), map(), keyword()) :: Ecto.Query.t()
  def apply_raw(query, params, opts \\ []) when is_map(params) do
    allowed_fields = Keyword.get(opts, :allowed_fields)
    schema = Keyword.get(opts, :schema)

    ast_maps =
      params
      |> Enum.flat_map(fn {key, value} ->
        case PgRest.Parser.parse_operator_value(value) do
          {:ok, op, val} -> [%{field: key, operator: op, value: val}]
          {:error, _} -> []
        end
      end)
      |> maybe_filter_allowed_maps(allowed_fields)

    ast_maps = maybe_cast(ast_maps, schema)

    PgRest.Filter.apply_all(query, ast_maps)
  end

  # Convert a Filter struct to one or more PgRest AST maps
  defp to_ast_maps(%Filter{operator: :gte_lte, field: field, value: {start_val, end_val}}) do
    field_str = Atom.to_string(field)

    [{start_val, :gte}, {end_val, :lte}]
    |> Enum.reject(fn {val, _op} -> is_nil(val) end)
    |> Enum.map(fn {val, op} -> %{field: field_str, operator: op, value: val} end)
  end

  # ILIKE/LIKE need % wildcards for substring matching
  defp to_ast_maps(%Filter{field: field, operator: op, value: value})
       when op in [:ilike, :like] and is_binary(value) do
    [%{field: Atom.to_string(field), operator: op, value: "%#{value}%"}]
  end

  # Note: :not_in is handled separately in apply/3 to avoid PgRest NOT wrapper issues

  defp to_ast_maps(%Filter{field: field, operator: op, value: value}) do
    [%{field: Atom.to_string(field), operator: op, value: value}]
  end

  defp maybe_filter_allowed(filters, nil), do: filters

  defp maybe_filter_allowed(filters, allowed_fields) do
    Enum.filter(filters, &(&1.field in allowed_fields))
  end

  defp maybe_filter_allowed_maps(maps, nil), do: maps

  defp maybe_filter_allowed_maps(maps, allowed_fields) do
    allowed_strings = Enum.map(allowed_fields, &Atom.to_string/1)
    Enum.filter(maps, &(&1.field in allowed_strings))
  end

  defp maybe_cast(ast_maps, nil), do: ast_maps

  defp maybe_cast(ast_maps, schema) do
    {:ok, cast} = PgRest.TypeCaster.cast_filters(ast_maps, schema)
    cast
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
