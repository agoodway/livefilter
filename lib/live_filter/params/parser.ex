defmodule LiveFilter.Params.Parser do
  @moduledoc """
  Converts PostgREST URL query params into a list of Filter structs,
  matched against a provided filter config list.

  Reuses `PgRest.Parser.parse_operator_value/1` for operator parsing.
  """

  alias LiveFilter.{Filter, FilterConfig}

  @doc """
  Parses URL params into `{filters, remaining_params}`.

  Matches each param against the config list by field name or custom_param.
  Merges paired gte/lte params into a single date_range filter.
  Unrecognized params are returned as remaining.
  """
  @spec from_params(map(), [FilterConfig.t()]) :: {[Filter.t()], map()}
  def from_params(params, configs) when is_map(params) and is_list(configs) do
    config_map = build_config_map(configs)

    # Extract date range filters from "and" param first
    {and_filters, remaining_and} = parse_and_param(params, config_map)

    # Remove consumed "and" param if fully processed, otherwise keep remainder
    params = update_and_param(params, remaining_and)

    {matched, remaining} = partition_params(params, config_map)
    filters = build_filters(matched, config_map)

    # Add always_on filters that weren't in params
    all_filters = filters ++ and_filters
    always_on_filters = build_always_on_filters(configs, all_filters)

    {all_filters ++ always_on_filters, remaining}
  end

  # Parse the "and" param to extract date range filters
  # Returns {date_range_filters, remaining_and_conditions}
  defp parse_and_param(%{"and" => and_str}, config_map) when is_binary(and_str) do
    inner = and_str |> String.trim_leading("(") |> String.trim_trailing(")")
    conditions = split_and_conditions(inner)

    {date_range_conditions, other_conditions} =
      Enum.split_with(conditions, &date_range_condition?(&1, config_map))

    filters = build_date_range_from_conditions(date_range_conditions, config_map)

    remaining =
      case other_conditions do
        [] -> nil
        conds -> "(#{Enum.join(conds, ",")})"
      end

    {filters, remaining}
  end

  defp parse_and_param(_params, _config_map), do: {[], nil}

  defp update_and_param(params, nil), do: Map.delete(params, "and")
  defp update_and_param(params, ""), do: Map.delete(params, "and")
  defp update_and_param(params, rest), do: Map.put(params, "and", rest)

  defp date_range_condition?(cond, config_map) do
    case parse_condition_field_op(cond) do
      {field, op} when op in [:gte, :lte] ->
        case find_config(field, config_map) do
          %{type: type} when type in [:date_range, :datetime_range] -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  # Valid operators for date range conditions
  @date_range_operators ~w(gte lte)

  # Parse "field.op.value" -> {field, op}
  defp parse_condition_field_op(condition) do
    case String.split(condition, ".", parts: 3) do
      [field, op, _value] when op in @date_range_operators ->
        {field, String.to_existing_atom(op)}

      _ ->
        {nil, nil}
    end
  end

  # Build date range filters from conditions like ["due_date.gte.2026-02-01", "due_date.lte.2026-02-28"]
  defp build_date_range_from_conditions(conditions, config_map) do
    conditions
    |> Enum.group_by(&extract_condition_field/1)
    |> Enum.reject(fn {k, _} -> is_nil(k) end)
    |> Enum.flat_map(&build_date_range_filter_from_group(&1, config_map))
  end

  defp extract_condition_field(cond) do
    case String.split(cond, ".", parts: 3) do
      [field, _, _] -> field
      _ -> nil
    end
  end

  defp build_date_range_filter_from_group({field, field_conds}, config_map) do
    case {find_config(field, config_map), extract_date_range_values(field_conds)} do
      {%{type: type} = config, {gte_val, lte_val}}
      when type in [:date_range, :datetime_range] and
             (not is_nil(gte_val) or not is_nil(lte_val)) ->
        [Filter.new(config, :gte_lte, {gte_val, lte_val})]

      _ ->
        []
    end
  end

  defp extract_date_range_values(field_conds) do
    Enum.reduce(field_conds, {nil, nil}, fn cond, {gte, lte} ->
      case String.split(cond, ".", parts: 3) do
        [_, "gte", val] -> {val, lte}
        [_, "lte", val] -> {gte, val}
        _ -> {gte, lte}
      end
    end)
  end

  # Split on commas, but respect nested parentheses (for in.(...) etc.)
  defp split_and_conditions(str), do: do_split(str, 0, "", [])

  defp do_split("", _depth, "", acc), do: Enum.reverse(acc)
  defp do_split("", _depth, current, acc), do: Enum.reverse([current | acc])

  defp do_split("(" <> rest, depth, current, acc),
    do: do_split(rest, depth + 1, current <> "(", acc)

  defp do_split(")" <> rest, depth, current, acc) when depth > 0,
    do: do_split(rest, depth - 1, current <> ")", acc)

  defp do_split("," <> rest, 0, current, acc),
    do: do_split(rest, 0, "", [current | acc])

  defp do_split(<<char::binary-size(1), rest::binary>>, depth, current, acc),
    do: do_split(rest, depth, current <> char, acc)

  # Build lookup maps: field_name -> config and custom_param -> config
  defp build_config_map(configs) do
    by_field =
      configs
      |> Enum.map(fn c -> {Atom.to_string(c.field), c} end)
      |> Map.new()

    by_custom =
      configs
      |> Enum.filter(& &1.custom_param)
      |> Enum.map(fn c -> {c.custom_param, c} end)
      |> Map.new()

    %{by_field: by_field, by_custom: by_custom}
  end

  defp partition_params(params, config_map) do
    Enum.reduce(params, {[], %{}}, fn {key, value}, {matched, remaining} ->
      case find_config(key, config_map) do
        nil ->
          {matched, Map.put(remaining, key, value)}

        config ->
          {[{config, key, value} | matched], remaining}
      end
    end)
  end

  defp find_config(key, %{by_field: by_field, by_custom: by_custom}) do
    Map.get(by_custom, key) || Map.get(by_field, key)
  end

  defp build_filters(matched, _config_map) do
    matched
    |> Enum.group_by(fn {config, _key, _value} -> config.field end)
    |> Enum.flat_map(&build_filters_for_field/1)
    |> Enum.reject(&is_nil/1)
  end

  defp build_filters_for_field({_field, entries}) do
    [{config, _key, _value} | _] = entries

    case config.type do
      type when type in [:date_range, :datetime_range] ->
        build_date_range_filter(config, entries)

      _ ->
        Enum.map(entries, fn {c, _k, val} -> parse_single_filter(c, val) end)
    end
  end

  defp parse_single_filter(config, value) when is_binary(value) do
    case PgRest.Parser.parse_operator_value(value) do
      {:ok, op, val} ->
        val = post_process_value(op, val)
        Filter.new(config, op, val)

      {:error, _} ->
        # For custom params without operator prefix, use default operator
        Filter.new(config, config.default_operator, value)
    end
  end

  defp parse_single_filter(config, value) do
    Filter.new(config, config.default_operator, value)
  end

  # Post-process parsed values based on operator
  defp post_process_value(:ilike, val), do: strip_wildcards(val)

  # Array operators: parse {a,b,c} format into list
  defp post_process_value(op, val) when op in [:cs, :cd, :ov] and is_binary(val) do
    parse_array_value(val)
  end

  defp post_process_value(_op, val), do: val

  defp strip_wildcards(val) when is_binary(val) do
    val
    |> String.trim_leading("*")
    |> String.trim_trailing("*")
  end

  defp strip_wildcards(val), do: val

  # Parse PostgREST array format: {a,b,c} -> ["a", "b", "c"]
  defp parse_array_value("{" <> rest) do
    rest
    |> String.trim_trailing("}")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp parse_array_value(val), do: [val]

  # Date range: merge gte/lte param pairs into a single filter
  defp build_date_range_filter(config, entries) do
    all_values =
      entries
      |> Enum.flat_map(fn {_config, _key, value} -> List.wrap(value) end)

    case extract_range_bounds(all_values) do
      {nil, nil} -> []
      {gte_val, lte_val} -> [Filter.new(config, :gte_lte, {gte_val, lte_val})]
    end
  end

  defp extract_range_bounds(values) do
    Enum.reduce(values, {nil, nil}, fn value, {gte, lte} ->
      case PgRest.Parser.parse_operator_value(value) do
        {:ok, :gte, val} -> {val, lte}
        {:ok, :lte, val} -> {gte, val}
        _ -> {gte, lte}
      end
    end)
  end

  # Create filters for always_on configs that weren't matched in params
  defp build_always_on_filters(configs, existing_filters) do
    existing_fields = MapSet.new(existing_filters, & &1.field)

    configs
    |> Enum.filter(& &1.always_on)
    |> Enum.reject(&MapSet.member?(existing_fields, &1.field))
    |> Enum.map(&Filter.new/1)
  end
end
