defmodule LiveFilter.QueryBuilder do
  @moduledoc """
  Thin query builder that converts LiveFilter structs to PgRest AST maps
  and delegates to `PgRest.Filter.apply_all/2`.
  """

  import Kernel, except: [apply: 3]
  import Ecto.Query, only: [limit: 2, offset: 2, exclude: 2]

  alias LiveFilter.{Filter, Pagination}
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

    ast_maps =
      filters
      |> maybe_filter_allowed(allowed_fields)
      |> Enum.reject(&empty_value?/1)
      |> Enum.flat_map(&to_ast_maps/1)

    ast_maps = maybe_cast(ast_maps, schema)

    PgRest.Filter.apply_all(query, ast_maps)
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
