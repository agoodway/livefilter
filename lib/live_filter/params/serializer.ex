defmodule LiveFilter.Params.Serializer do
  @moduledoc """
  Converts a list of active Filter structs into a PostgREST-compatible query param map.
  """

  alias LiveFilter.{Filter, Pagination}

  @doc """
  Serializes a list of filters to a PostgREST-compatible param map.

  Nil and empty string values are excluded. Date range filters produce two
  params (gte + lte). Ilike text filters auto-wrap with `*` wildcards if
  not already present.
  """
  @spec to_params([Filter.t()]) :: map()
  def to_params(filters) when is_list(filters) do
    {date_range_filters, other_filters} =
      filters
      |> Enum.reject(&skip_filter?/1)
      |> Enum.split_with(&date_range_filter?/1)

    # Build params from non-date-range filters
    params = Enum.reduce(other_filters, %{}, &serialize_filter/2)

    # Add date range filters using PostgREST and() syntax
    add_date_range_params(params, date_range_filters)
  end

  defp skip_filter?(%Filter{value: nil}), do: true
  defp skip_filter?(%Filter{value: ""}), do: true
  defp skip_filter?(%Filter{value: {nil, nil}}), do: true
  defp skip_filter?(_), do: false

  defp date_range_filter?(%Filter{operator: :gte_lte}), do: true
  defp date_range_filter?(_), do: false

  # Date range filters use the and() syntax to combine gte/lte on same field
  # e.g., and=(due_date.gte.2026-02-01,due_date.lte.2026-02-28)
  defp add_date_range_params(params, []), do: params

  defp add_date_range_params(params, date_range_filters) do
    conditions =
      date_range_filters
      |> Enum.flat_map(&date_range_conditions/1)
      |> Enum.join(",")

    case {conditions, Map.get(params, "and", "")} do
      {"", _} -> params
      {conds, ""} -> Map.put(params, "and", "(#{conds})")
      {conds, existing} -> Map.put(params, "and", merge_and_conditions(existing, conds))
    end
  end

  defp merge_and_conditions("(" <> rest, new_conditions) do
    # Strip trailing ) and merge
    existing = String.trim_trailing(rest, ")")
    "(#{existing},#{new_conditions})"
  end

  defp merge_and_conditions(existing, new_conditions) do
    "(#{existing},#{new_conditions})"
  end

  defp date_range_conditions(%Filter{operator: :gte_lte, value: {start_val, end_val}} = filter) do
    field = param_key(filter)

    [{start_val, "gte"}, {end_val, "lte"}]
    |> Enum.reject(fn {val, _op} -> is_nil(val) end)
    |> Enum.map(fn {val, op} -> "#{field}.#{op}.#{val}" end)
  end

  defp serialize_filter(%Filter{} = filter, acc) do
    key = param_key(filter)
    value = serialize_value(filter)
    Map.put(acc, key, value)
  end

  defp param_key(%Filter{config: %{custom_param: custom}}) when is_binary(custom), do: custom
  defp param_key(%Filter{field: field}), do: Atom.to_string(field)

  # Ilike: auto-wrap with * wildcards if not already present
  defp serialize_value(%Filter{operator: :ilike, value: value}) when is_binary(value) do
    wrapped =
      value
      |> maybe_prepend_wildcard()
      |> maybe_append_wildcard()

    "ilike.#{wrapped}"
  end

  # IN: list value -> in.(a,b,c)
  defp serialize_value(%Filter{operator: :in, value: values}) when is_list(values) do
    "in.(#{Enum.join(values, ",")})"
  end

  # IS: boolean -> is.true / is.false
  defp serialize_value(%Filter{operator: :is, value: true}), do: "is.true"
  defp serialize_value(%Filter{operator: :is, value: false}), do: "is.false"

  # IS NULL
  defp serialize_value(%Filter{operator: :is_null, value: true}), do: "is.null"
  defp serialize_value(%Filter{operator: :is_null, value: false}), do: "is.not_null"

  # Array containment/overlap: cs/cd/ov with list values
  defp serialize_value(%Filter{operator: op, value: values})
       when op in [:cs, :cd, :ov] and is_list(values) do
    "#{op}.{#{Enum.join(values, ",")}}"
  end

  # Default: op.value
  defp serialize_value(%Filter{operator: op, value: value}) do
    "#{op}.#{value}"
  end

  defp maybe_prepend_wildcard("*" <> _ = val), do: val
  defp maybe_prepend_wildcard(val), do: "*" <> val

  defp maybe_append_wildcard(val) do
    if String.ends_with?(val, "*"), do: val, else: val <> "*"
  end

  @doc """
  Converts a params map to a raw query string without percent-encoding.

  This produces cleaner URLs like `tags=ov.{testing,bug}` instead of
  `tags=ov.%7Btesting%2Cbug%7D`.

  ## Example

      iex> Serializer.to_query_string(%{"status" => "eq.active", "tags" => "ov.{a,b}"})
      "status=eq.active&tags=ov.{a,b}"
  """
  @spec to_query_string(map()) :: String.t()
  def to_query_string(params) when is_map(params) do
    Enum.map_join(params, "&", fn {key, value} -> "#{key}=#{value}" end)
  end

  @doc """
  Builds a full path with raw query string.

  ## Example

      iex> Serializer.to_path("/tasks", %{"status" => "eq.active"})
      "/tasks?status=eq.active"
  """
  @spec to_path(String.t(), map()) :: String.t()
  def to_path(base_path, params) when is_map(params) do
    case to_query_string(params) do
      "" -> base_path
      qs -> "#{base_path}?#{qs}"
    end
  end

  @doc """
  Serializes pagination state to PostgREST-compatible URL params.

  ## Example

      iex> pagination = %LiveFilter.Pagination{limit: 25, offset: 50}
      iex> Serializer.pagination_to_params(pagination)
      %{"limit" => "25", "offset" => "50"}
  """
  @spec pagination_to_params(Pagination.t()) :: map()
  def pagination_to_params(%Pagination{limit: limit, offset: offset}) do
    %{"limit" => to_string(limit), "offset" => to_string(offset)}
  end
end
