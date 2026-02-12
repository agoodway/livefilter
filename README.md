# LiveFilter: Composable List View Filtering for Phoenix LiveView

## Executive Summary

LiveFilter is a composable, URL-driven filtering library for Phoenix LiveView that provides Linear/Notion/Airtable-style filter UIs. Users click to add filters, choose operators, enter values — and the library produces PostgREST/Supabase-compatible query parameters that are both shareable as URLs and convertible to Ecto queries via a pluggable adapter system.

**Companion Library:** LiveFilter's query builder is designed to integrate with **ExRest**, sharing the same PostgREST-compatible URL parameter format and operator semantics.

**Core Approach:**

```elixir
defmodule MyAppWeb.OrdersLive do
  use MyAppWeb, :live_view

  # Define available filters for this view
  @filter_config [
    LiveFilter.text(:reference, label: "Reference"),
    LiveFilter.select(:status, label: "Status", options: ~w(pending confirmed shipped delivered)),
    LiveFilter.multi_select(:tags, label: "Tags", options_fn: &fetch_tags/0),
    LiveFilter.date_range(:inserted_at, label: "Created"),
    LiveFilter.boolean(:urgent, label: "Urgent"),
    LiveFilter.number(:total, label: "Total", operators: [:gte, :lte, :eq])
  ]

  def mount(params, _session, socket) do
    # Hydrate filters from URL params (shareable links)
    {filter_state, query_params} = LiveFilter.from_params(params, @filter_config)

    socket =
      socket
      |> LiveFilter.init(@filter_config, filter_state)
      |> load_orders(query_params)

    {:ok, socket}
  end

  def handle_info({:live_filter, :updated, query_params}, socket) do
    # Filters changed → rebuild query, push URL params
    socket =
      socket
      |> load_orders(query_params)
      |> push_patch(to: ~p"/orders?#{query_params}")

    {:noreply, socket}
  end

  defp load_orders(socket, query_params) do
    query =
      Order
      |> where([o], o.tenant_id == ^socket.assigns.tenant_id)
      |> LiveFilter.QueryBuilder.apply(query_params, adapter: :postgres)
      |> order_by([o], desc: o.inserted_at)

    assign(socket, :orders, Repo.all(query))
  end

  def render(assigns) do
    ~H"""
    <LiveFilter.bar filter={@live_filter} />
    <.table rows={@orders}>
      <%!-- table columns --%>
    </.table>
    """
  end
end
```

**Key Features:**
- **PostgREST/ExRest Compatible** — Filter state serializes to `?status=eq.active&total=gte.100` URL params
- **Shareable URLs** — Copy/paste a filtered view link; LiveView hydrates filters from params on mount
- **Composable Filter Types** — Text search, select, multi-select, date, date range, boolean, number, with extensible type system
- **Pluggable Query Builder** — Adapter pattern (Postgres first) converts params → Ecto queries
- **LiveView Native** — Stateful LiveComponent with live updates, no JS framework dependency
- **DaisyUI Styled** — Built on `daisy_ui_components` for dropdown, badge, input, select primitives
- **Saved Filter Sets** — Optional persistence of named filter combinations ("Views")

**Data Flow:**
```
User clicks "Add Filter" → picks field → picks operator → enters value
    ↓
LiveFilter state updates (list of %Filter{} structs)
    ↓
Serialize to PostgREST-compatible query params
    ↓
push_patch updates URL (shareable)
    ↓
Parent LiveView receives {:live_filter, :updated, params}
    ↓
QueryBuilder.apply(base_query, params, adapter: :postgres) → Ecto query
    ↓
Repo.all(query) → results
```

**Reverse flow (URL → UI):**
```
User visits /orders?status=eq.active&total=gte.100
    ↓
LiveFilter.from_params(params, config) → hydrate filter state
    ↓
UI renders active filter badges with correct values
```

---

## Part 1: Architecture Overview

### 1.1 Library Boundaries

LiveFilter is three distinct concerns packaged together:

```
┌──────────────────────────────────────────────────────────┐
│  LiveFilter                                              │
│                                                          │
│  ┌────────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │  UI Layer       │  │  Param Layer │  │  Query Layer │ │
│  │                │  │              │  │              │ │
│  │  LiveComponent │  │  Serializer  │  │  QueryBuilder│ │
│  │  Filter types  │→→│  Parser      │→→│  Adapters    │ │
│  │  DaisyUI       │  │  Validator   │  │  (Postgres)  │ │
│  └────────────────┘  └──────────────┘  └──────────────┘ │
│                                                          │
│  UI depends on Param Layer                               │
│  Query Layer depends on Param Layer                      │
│  UI and Query Layer are independent of each other        │
└──────────────────────────────────────────────────────────┘
```

This separation means:
- **Param Layer** can be used standalone (serialize/parse PostgREST params without LiveView)
- **Query Layer** can be used standalone (apply PostgREST params to Ecto queries without UI)
- **UI Layer** requires both, but the three are independently testable

### 1.2 Core Data Types

```elixir
defmodule LiveFilter.Types do
  @moduledoc """
  Core types used throughout LiveFilter.
  """

  @type operator :: :eq | :neq | :gt | :gte | :lt | :lte |
                    :like | :ilike | :in | :is | :cs | :cd |
                    :fts | :plfts

  @type filter_type :: :text | :number | :select | :multi_select |
                       :date | :datetime | :date_range | :boolean

  @type filter_value :: String.t() | number() | boolean() |
                        [String.t()] | Date.t() | DateTime.t() |
                        {Date.t(), Date.t()}
end
```

### 1.3 Filter Configuration

Each filterable field is defined by a config struct:

```elixir
defmodule LiveFilter.FilterConfig do
  @moduledoc """
  Defines a filterable field: its type, allowed operators, UI options,
  and how it maps to query parameters.
  """

  @type t :: %__MODULE__{
    field: atom(),
    type: LiveFilter.Types.filter_type(),
    label: String.t(),
    operators: [LiveFilter.Types.operator()],
    default_operator: LiveFilter.Types.operator(),
    options: [option()] | nil,
    options_fn: (-> [option()]) | nil,
    placeholder: String.t() | nil,
    always_on: boolean(),
    default_value: term() | nil,
    query_field: atom() | nil,       # Override: use different DB column
    custom_param: String.t() | nil   # Override: use handle_param instead of standard operator
  }

  @type option :: String.t() | {String.t(), String.t()}

  defstruct [
    :field, :type, :label, :placeholder, :default_value,
    :options, :options_fn, :query_field, :custom_param,
    operators: [],
    default_operator: :eq,
    always_on: false
  ]
end
```

### 1.4 Filter State (Active Filters)

Each active filter the user has applied:

```elixir
defmodule LiveFilter.Filter do
  @moduledoc """
  Represents a single active filter applied by the user.
  """

  @type t :: %__MODULE__{
    id: String.t(),
    field: atom(),
    operator: LiveFilter.Types.operator(),
    value: LiveFilter.Types.filter_value(),
    config: LiveFilter.FilterConfig.t()
  }

  defstruct [:id, :field, :operator, :value, :config]

  @doc "Generate a unique ID for this filter instance."
  def new(config, operator \\ nil, value \\ nil) do
    %__MODULE__{
      id: generate_id(),
      field: config.field,
      operator: operator || config.default_operator,
      value: value,
      config: config
    }
  end

  defp generate_id, do: Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
end
```

### 1.5 Filter Type Definitions (Builder Functions)

Convenience functions to define filter configs — the developer-facing API:

```elixir
defmodule LiveFilter do
  @moduledoc """
  Public API for defining filter configurations.
  """

  alias LiveFilter.FilterConfig

  @doc "Text search filter with ilike/like/eq operators."
  def text(field, opts \\ []) do
    %FilterConfig{
      field: field,
      type: :text,
      label: opts[:label] || humanize(field),
      operators: opts[:operators] || [:ilike, :eq, :neq, :like],
      default_operator: opts[:default_operator] || :ilike,
      placeholder: opts[:placeholder] || "Search...",
      always_on: opts[:always_on] || false,
      query_field: opts[:query_field],
      custom_param: opts[:custom_param]
    }
  end

  @doc "Number filter with comparison operators."
  def number(field, opts \\ []) do
    %FilterConfig{
      field: field,
      type: :number,
      label: opts[:label] || humanize(field),
      operators: opts[:operators] || [:eq, :neq, :gt, :gte, :lt, :lte],
      default_operator: opts[:default_operator] || :eq,
      placeholder: opts[:placeholder]
    }
  end

  @doc "Single-select dropdown filter."
  def select(field, opts \\ []) do
    %FilterConfig{
      field: field,
      type: :select,
      label: opts[:label] || humanize(field),
      operators: opts[:operators] || [:eq, :neq],
      default_operator: :eq,
      options: opts[:options],
      options_fn: opts[:options_fn]
    }
  end

  @doc "Multi-select filter (produces `in` operator)."
  def multi_select(field, opts \\ []) do
    %FilterConfig{
      field: field,
      type: :multi_select,
      label: opts[:label] || humanize(field),
      operators: opts[:operators] || [:in],
      default_operator: :in,
      options: opts[:options],
      options_fn: opts[:options_fn]
    }
  end

  @doc "Date filter with comparison operators."
  def date(field, opts \\ []) do
    %FilterConfig{
      field: field,
      type: :date,
      label: opts[:label] || humanize(field),
      operators: opts[:operators] || [:eq, :gt, :gte, :lt, :lte],
      default_operator: opts[:default_operator] || :eq
    }
  end

  @doc "Date range filter (from..to)."
  def date_range(field, opts \\ []) do
    %FilterConfig{
      field: field,
      type: :date_range,
      label: opts[:label] || humanize(field),
      operators: [:gte_lte],  # Special compound operator
      default_operator: :gte_lte
    }
  end

  @doc "DateTime filter."
  def datetime(field, opts \\ []) do
    %FilterConfig{
      field: field,
      type: :datetime,
      label: opts[:label] || humanize(field),
      operators: opts[:operators] || [:eq, :gt, :gte, :lt, :lte],
      default_operator: opts[:default_operator] || :gte
    }
  end

  @doc "Boolean toggle filter."
  def boolean(field, opts \\ []) do
    %FilterConfig{
      field: field,
      type: :boolean,
      label: opts[:label] || humanize(field),
      operators: [:is],
      default_operator: :is,
      default_value: opts[:default_value]
    }
  end

  defp humanize(field) do
    field |> to_string() |> String.replace("_", " ") |> String.capitalize()
  end
end
```

---

## Part 2: Param Layer — Serialization & Parsing

### 2.1 PostgREST-Compatible Parameter Format

LiveFilter serializes filter state to URL query parameters using the same format as PostgREST/Supabase/ExRest:

```
Single filter:     ?{field}={operator}.{value}
Multiple filters:  ?status=eq.active&total=gte.100&name=ilike.*smith*
Multi-select (in): ?status=in.(active,pending,shipped)
Boolean (is):      ?urgent=is.true
Date range:        ?inserted_at=gte.2024-01-01&inserted_at=lte.2024-02-01
Null check:        ?deleted_at=is.null
```

This format is identical to ExRest URL filters (Part 2.7 of ExRest README), ensuring full compatibility.

### 2.2 Serializer (Filter State → Params)

```elixir
defmodule LiveFilter.Params.Serializer do
  @moduledoc """
  Converts active filter state to PostgREST-compatible query parameters.
  """

  alias LiveFilter.Filter

  @doc """
  Serialize a list of active filters to a query param map.

  Returns a map suitable for URI.encode_query/1 or push_patch.
  Handles compound filters (date_range) by emitting multiple params.
  """
  @spec to_params([Filter.t()]) :: %{String.t() => String.t() | [String.t()]}
  def to_params(filters) when is_list(filters) do
    filters
    |> Enum.reject(fn f -> is_nil(f.value) or f.value == "" end)
    |> Enum.flat_map(&serialize_filter/1)
    |> merge_params()
  end

  defp serialize_filter(%Filter{config: %{type: :date_range}} = f) do
    case f.value do
      {start_date, end_date} ->
        field = to_string(f.field)
        [
          {field, "gte.#{Date.to_iso8601(start_date)}"},
          {field, "lte.#{Date.to_iso8601(end_date)}"}
        ]
      _ -> []
    end
  end

  defp serialize_filter(%Filter{config: %{type: :multi_select}} = f) do
    values = f.value |> Enum.join(",")
    [{to_string(f.field), "in.(#{values})"}]
  end

  defp serialize_filter(%Filter{config: %{type: :boolean}} = f) do
    [{to_string(f.field), "is.#{f.value}"}]
  end

  defp serialize_filter(%Filter{config: %{custom_param: param}} = f) when not is_nil(param) do
    # Custom params bypass the operator format (e.g., ?search=foo)
    [{param, to_string(f.value)}]
  end

  defp serialize_filter(%Filter{} = f) do
    [{to_string(f.field), "#{f.operator}.#{encode_value(f.value)}"}]
  end

  defp encode_value(value) when is_binary(value), do: value
  defp encode_value(%Date{} = d), do: Date.to_iso8601(d)
  defp encode_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp encode_value(value), do: to_string(value)

  # When a field appears multiple times (e.g., date range), collect into list
  defp merge_params(pairs) do
    Enum.reduce(pairs, %{}, fn {key, value}, acc ->
      Map.update(acc, key, value, fn
        existing when is_list(existing) -> existing ++ [value]
        existing -> [existing, value]
      end)
    end)
  end
end
```

### 2.3 Parser (Params → Filter State)

```elixir
defmodule LiveFilter.Params.Parser do
  @moduledoc """
  Parses PostgREST-style URL params back into LiveFilter state.
  Used to hydrate the UI from a shareable URL.
  """

  alias LiveFilter.{Filter, FilterConfig}

  @operators ~w(eq neq gt gte lt lte like ilike in is cs cd fts plfts phfts)

  @doc """
  Parse URL params against a filter config list.

  Returns {filter_state, remaining_query_params}.
  Unrecognized params are passed through (they may be custom params
  handled by ExRest's handle_param/4 or pagination/ordering).
  """
  @spec from_params(map(), [FilterConfig.t()]) :: {[Filter.t()], map()}
  def from_params(params, configs) when is_map(params) and is_list(configs) do
    config_by_field = Map.new(configs, &{to_string(&1.field), &1})
    config_by_custom = configs
      |> Enum.filter(& &1.custom_param)
      |> Map.new(&{&1.custom_param, &1})

    {filters, remaining} =
      Enum.reduce(params, {[], %{}}, fn {key, value}, {filters, rest} ->
        cond do
          config = Map.get(config_by_field, key) ->
            parsed = parse_param_value(value, config)
            {filters ++ parsed, rest}

          config = Map.get(config_by_custom, key) ->
            filter = Filter.new(config, config.default_operator, value)
            {[filter | filters], rest}

          true ->
            {filters, Map.put(rest, key, value)}
        end
      end)

    # Merge date_range pairs
    filters = merge_range_filters(filters, configs)

    {filters, remaining}
  end

  defp parse_param_value(values, config) when is_list(values) do
    # Multiple values for same field (e.g., date range: gte + lte)
    Enum.map(values, &parse_single_value(&1, config))
  end

  defp parse_param_value(value, config) when is_binary(value) do
    [parse_single_value(value, config)]
  end

  defp parse_single_value(value, config) do
    case String.split(value, ".", parts: 2) do
      [op, rest] when op in @operators ->
        operator = String.to_existing_atom(op)
        parsed_value = parse_value(rest, config.type, operator)
        Filter.new(config, operator, parsed_value)

      _ ->
        # No recognized operator prefix — treat as eq
        Filter.new(config, :eq, value)
    end
  end

  defp parse_value("(" <> rest, :multi_select, :in) do
    rest |> String.trim_trailing(")") |> String.split(",")
  end

  defp parse_value(value, :date, _op), do: Date.from_iso8601!(value)
  defp parse_value(value, :date_range, _op), do: Date.from_iso8601!(value)
  defp parse_value(value, :datetime, _op), do: DateTime.from_iso8601(value) |> elem(1)
  defp parse_value("true", :boolean, :is), do: true
  defp parse_value("false", :boolean, :is), do: false
  defp parse_value("null", _, :is), do: nil
  defp parse_value(value, :number, _op), do: parse_number(value)
  defp parse_value(value, _, _), do: value

  defp parse_number(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ ->
        case Float.parse(value) do
          {float, ""} -> float
          _ -> value
        end
    end
  end

  defp merge_range_filters(filters, configs) do
    range_configs = Enum.filter(configs, &(&1.type == :date_range))

    Enum.reduce(range_configs, filters, fn config, acc ->
      {range_filters, other} = Enum.split_with(acc, &(&1.field == config.field))

      case range_filters do
        [%{operator: :gte, value: start_val}, %{operator: :lte, value: end_val}] ->
          [Filter.new(config, :gte_lte, {start_val, end_val}) | other]

        [%{operator: :lte, value: end_val}, %{operator: :gte, value: start_val}] ->
          [Filter.new(config, :gte_lte, {start_val, end_val}) | other]

        _ ->
          acc  # Can't merge, leave as-is
      end
    end)
  end
end
```

### 2.4 Param Validation

```elixir
defmodule LiveFilter.Params.Validator do
  @moduledoc """
  Validates that parsed filter values are safe and well-typed.
  Prevents injection through URL params.
  """

  alias LiveFilter.{Filter, FilterConfig}

  @max_value_length 500
  @max_in_values 100

  @doc "Validate a list of parsed filters against their configs."
  @spec validate([Filter.t()]) :: {:ok, [Filter.t()]} | {:error, [String.t()]}
  def validate(filters) do
    errors =
      filters
      |> Enum.flat_map(&validate_filter/1)

    case errors do
      [] -> {:ok, filters}
      errors -> {:error, errors}
    end
  end

  defp validate_filter(%Filter{} = f) do
    [
      validate_operator(f),
      validate_value_type(f),
      validate_value_length(f)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp validate_operator(%{operator: op, config: config}) do
    unless op in config.operators or op in [:gte_lte] do
      "Invalid operator #{op} for field #{config.field}"
    end
  end

  defp validate_value_type(%{value: value, config: %{type: :number}}) when is_binary(value) do
    "Expected number for field, got string"
  end
  defp validate_value_type(_), do: nil

  defp validate_value_length(%{value: value}) when is_binary(value) and byte_size(value) > @max_value_length do
    "Value exceeds maximum length of #{@max_value_length}"
  end
  defp validate_value_length(%{value: values}) when is_list(values) and length(values) > @max_in_values do
    "Too many values in list (max #{@max_in_values})"
  end
  defp validate_value_length(_), do: nil
end
```

---

## Part 3: Query Layer — Ecto Query Builder

### 3.1 Adapter Behavior

```elixir
defmodule LiveFilter.QueryBuilder.Adapter do
  @moduledoc """
  Behavior for database-specific query building.
  Adapters convert PostgREST-style params to Ecto query fragments.
  """

  @callback apply_filter(
    query :: Ecto.Query.t(),
    field :: atom(),
    operator :: atom(),
    value :: term()
  ) :: Ecto.Query.t()

  @callback supported_operators() :: [atom()]
end
```

### 3.2 Postgres Adapter

```elixir
defmodule LiveFilter.QueryBuilder.Adapters.Postgres do
  @moduledoc """
  PostgreSQL adapter for LiveFilter query building.
  Converts PostgREST-style operator/value pairs to Ecto query clauses.
  """

  @behaviour LiveFilter.QueryBuilder.Adapter

  import Ecto.Query

  @impl true
  def supported_operators do
    [:eq, :neq, :gt, :gte, :lt, :lte, :like, :ilike, :in, :is,
     :cs, :cd, :fts, :plfts, :phfts, :gte_lte]
  end

  @impl true
  def apply_filter(query, field, :eq, value) do
    where(query, [r], field(r, ^field) == ^value)
  end

  def apply_filter(query, field, :neq, value) do
    where(query, [r], field(r, ^field) != ^value)
  end

  def apply_filter(query, field, :gt, value) do
    where(query, [r], field(r, ^field) > ^value)
  end

  def apply_filter(query, field, :gte, value) do
    where(query, [r], field(r, ^field) >= ^value)
  end

  def apply_filter(query, field, :lt, value) do
    where(query, [r], field(r, ^field) < ^value)
  end

  def apply_filter(query, field, :lte, value) do
    where(query, [r], field(r, ^field) <= ^value)
  end

  def apply_filter(query, field, :like, value) do
    where(query, [r], like(field(r, ^field), ^value))
  end

  def apply_filter(query, field, :ilike, value) do
    pattern = if String.contains?(value, "%"), do: value, else: "%#{value}%"
    where(query, [r], ilike(field(r, ^field), ^pattern))
  end

  def apply_filter(query, field, :in, values) when is_list(values) do
    where(query, [r], field(r, ^field) in ^values)
  end

  def apply_filter(query, field, :is, nil) do
    where(query, [r], is_nil(field(r, ^field)))
  end

  def apply_filter(query, field, :is, true) do
    where(query, [r], field(r, ^field) == true)
  end

  def apply_filter(query, field, :is, false) do
    where(query, [r], field(r, ^field) == false)
  end

  # Compound: date range (gte + lte in one filter)
  def apply_filter(query, field, :gte_lte, {start_val, end_val}) do
    query
    |> where([r], field(r, ^field) >= ^start_val)
    |> where([r], field(r, ^field) <= ^end_val)
  end

  # Array contains (@>)
  def apply_filter(query, field, :cs, value) do
    where(query, [r], fragment("? @> ?", field(r, ^field), ^value))
  end

  # Full-text search (plainto_tsquery)
  def apply_filter(query, field, :fts, value) do
    where(query, [r], fragment("? @@ plainto_tsquery(?)", field(r, ^field), ^value))
  end

  def apply_filter(query, field, :plfts, value) do
    where(query, [r], fragment("? @@ plainto_tsquery(?)", field(r, ^field), ^value))
  end

  def apply_filter(query, field, :phfts, value) do
    where(query, [r], fragment("? @@ phraseto_tsquery(?)", field(r, ^field), ^value))
  end
end
```

### 3.3 QueryBuilder (Public API)

```elixir
defmodule LiveFilter.QueryBuilder do
  @moduledoc """
  Applies LiveFilter params to an Ecto query using a pluggable adapter.

  ## Usage

      Order
      |> where([o], o.tenant_id == ^tenant_id)
      |> LiveFilter.QueryBuilder.apply(query_params, adapter: :postgres)
      |> Repo.all()

  ## With raw PostgREST-style param map

      LiveFilter.QueryBuilder.apply(Order, %{
        "status" => "eq.active",
        "total" => "gte.100"
      })
  """

  alias LiveFilter.Params.Parser
  alias LiveFilter.QueryBuilder.Adapters

  @default_adapter Adapters.Postgres

  @doc """
  Apply PostgREST-style query params to an Ecto query.

  Accepts either:
  - A pre-parsed filter list (from LiveFilter UI)
  - A raw param map (from URL params or ExRest)

  Options:
  - `:adapter` — `:postgres` (default), or a module implementing Adapter behavior
  - `:config` — filter config list (required if passing raw param map)
  - `:allowed_fields` — whitelist of field atoms (security)
  """
  @spec apply(Ecto.Query.t(), map() | [LiveFilter.Filter.t()], keyword()) :: Ecto.Query.t()
  def apply(query, params, opts \\ [])

  def apply(query, filters, opts) when is_list(filters) do
    adapter = resolve_adapter(opts[:adapter])
    allowed = opts[:allowed_fields]

    Enum.reduce(filters, query, fn filter, q ->
      field = filter.field
      if allowed && field not in allowed, do: q,
      else: adapter.apply_filter(q, field, filter.operator, filter.value)
    end)
  end

  def apply(query, params, opts) when is_map(params) do
    config = Keyword.fetch!(opts, :config)
    {filters, _remaining} = Parser.from_params(params, config)
    apply(query, filters, opts)
  end

  @doc """
  Apply raw PostgREST param string to a query.
  Parses `field=op.value` format directly without filter config.
  Useful for ExRest integration where schema provides validation.
  """
  @spec apply_raw(Ecto.Query.t(), map(), keyword()) :: Ecto.Query.t()
  def apply_raw(query, params, opts \\ []) do
    adapter = resolve_adapter(opts[:adapter])
    allowed = opts[:allowed_fields]

    Enum.reduce(params, query, fn {field_str, value_str}, q ->
      with {:ok, field} <- safe_to_atom(field_str),
           true <- is_nil(allowed) or field in allowed,
           {op, value} <- parse_operator_value(value_str) do
        adapter.apply_filter(q, field, op, value)
      else
        _ -> q
      end
    end)
  end

  defp resolve_adapter(nil), do: @default_adapter
  defp resolve_adapter(:postgres), do: Adapters.Postgres
  defp resolve_adapter(module) when is_atom(module), do: module

  defp safe_to_atom(field) do
    {:ok, String.to_existing_atom(field)}
  rescue
    ArgumentError -> :error
  end

  @operators ~w(eq neq gt gte lt lte like ilike in is cs cd fts plfts phfts)

  defp parse_operator_value(value) when is_binary(value) do
    case String.split(value, ".", parts: 2) do
      [op, rest] when op in @operators ->
        {String.to_existing_atom(op), parse_raw_value(rest, op)}
      _ ->
        {:eq, value}
    end
  end

  defp parse_raw_value("(" <> rest, "in") do
    rest |> String.trim_trailing(")") |> String.split(",")
  end
  defp parse_raw_value("true", "is"), do: true
  defp parse_raw_value("false", "is"), do: false
  defp parse_raw_value("null", "is"), do: nil
  defp parse_raw_value(value, _), do: value
end
```

### 3.4 ExRest Integration Point

LiveFilter's QueryBuilder can serve as the query-building engine for ExRest's URL filter pipeline, or be used independently:

```elixir
# Standalone (no ExRest)
Order
|> my_scope(context)
|> LiveFilter.QueryBuilder.apply(url_params, config: @filter_config, adapter: :postgres)
|> Repo.all()

# With ExRest — ExRest can delegate URL filter application to LiveFilter's QueryBuilder
# or use its own (they produce identical Ecto queries from the same param format)
```

The shared contract is the **PostgREST param format**: `field=operator.value`. Both libraries parse and produce this format identically.

---

## Part 4: UI Layer — LiveView Components

### 4.1 Component Hierarchy

```
LiveFilter.Bar (LiveComponent)
├── LiveFilter.ActiveFilters          — Row of active filter badges
│   └── LiveFilter.FilterBadge       — Single badge: "Status = active" [×]
├── LiveFilter.AddFilterDropdown      — "+ Add filter" button + dropdown
│   └── LiveFilter.FieldPicker        — List of available fields
└── LiveFilter.FilterEditor           — Inline editor for a filter's value
    ├── LiveFilter.Inputs.Text        — Text input
    ├── LiveFilter.Inputs.Number      — Number input
    ├── LiveFilter.Inputs.Select      — Single select dropdown
    ├── LiveFilter.Inputs.MultiSelect — Multi-select with checkboxes
    ├── LiveFilter.Inputs.Date        — Date picker
    ├── LiveFilter.Inputs.DateRange   — From/To date pickers
    ├── LiveFilter.Inputs.DateTime    — DateTime picker
    └── LiveFilter.Inputs.Boolean     — Toggle switch
```

### 4.2 DaisyUI Component Mapping

LiveFilter builds on `daisy_ui_components` primitives:

| LiveFilter Component | DaisyUI Components Used |
|---------------------|------------------------|
| FilterBar container | `join` (horizontal group) |
| Add Filter button | `button` + `dropdown` |
| Field picker list | `menu` inside dropdown |
| Active filter badge | `badge` with close button |
| Filter editor popover | `dropdown` (click-to-open) |
| Text input | `text_input` (from core components) |
| Select | `select` (from core components) |
| Multi-select | Custom: checkboxes in dropdown using `checkbox` + `menu` |
| Date picker | Native HTML date input styled with DaisyUI `input` class |
| Boolean | `toggle` |
| Operator picker | Small `select` or `dropdown` |

### 4.3 LiveFilter.Bar (Main LiveComponent)

```elixir
defmodule LiveFilter.Bar do
  @moduledoc """
  Main LiveComponent that renders the filter bar.

  ## Usage in parent LiveView

      <LiveFilter.Bar
        id="orders-filter"
        config={@filter_config}
        filters={@active_filters}
        on_change={fn params -> send(self(), {:live_filter, :updated, params}) end}
      />

  Or using the convenience assigns from `LiveFilter.init/3`:

      <LiveFilter.bar filter={@live_filter} />
  """

  use Phoenix.LiveComponent

  alias LiveFilter.{Filter, Params}

  @impl true
  def mount(socket) do
    {:ok, assign(socket,
      editing_filter_id: nil,
      show_field_picker: false
    )}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:filters, fn -> [] end)

    {:ok, socket}
  end

  @impl true
  def handle_event("add_filter", %{"field" => field_name}, socket) do
    config = Enum.find(socket.assigns.config, &(to_string(&1.field) == field_name))

    if config do
      filter = Filter.new(config)
      filters = socket.assigns.filters ++ [filter]

      socket =
        socket
        |> assign(filters: filters, show_field_picker: false, editing_filter_id: filter.id)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_filter", %{"id" => id} = params, socket) do
    filters = Enum.map(socket.assigns.filters, fn f ->
      if f.id == id do
        operator = if params["operator"],
          do: String.to_existing_atom(params["operator"]),
          else: f.operator

        value = parse_input_value(params["value"], f.config.type)

        %{f | operator: operator, value: value}
      else
        f
      end
    end)

    socket = assign(socket, filters: filters)
    notify_parent(socket)
    {:noreply, socket}
  end

  def handle_event("remove_filter", %{"id" => id}, socket) do
    filters = Enum.reject(socket.assigns.filters, &(&1.id == id))
    socket = assign(socket, filters: filters, editing_filter_id: nil)
    notify_parent(socket)
    {:noreply, socket}
  end

  def handle_event("clear_all", _, socket) do
    always_on = Enum.filter(socket.assigns.filters, & &1.config.always_on)
    socket = assign(socket, filters: always_on, editing_filter_id: nil)
    notify_parent(socket)
    {:noreply, socket}
  end

  def handle_event("toggle_field_picker", _, socket) do
    {:noreply, update(socket, :show_field_picker, &(!&1))}
  end

  def handle_event("edit_filter", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_filter_id: id)}
  end

  def handle_event("close_editor", _, socket) do
    {:noreply, assign(socket, editing_filter_id: nil)}
  end

  defp notify_parent(socket) do
    params = Params.Serializer.to_params(socket.assigns.filters)
    socket.assigns.on_change.(params)
  end

  defp parse_input_value(value, :number) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ ->
        case Float.parse(value) do
          {float, ""} -> float
          _ -> nil
        end
    end
  end
  defp parse_input_value(value, :boolean), do: value == "true"
  defp parse_input_value(value, _type), do: value

  # Render — see Part 4.4 for template details
  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-2 p-2">
      <%!-- Always-on filters --%>
      <.always_on_filters filters={@filters} editing_id={@editing_filter_id} />

      <%!-- Active filter badges --%>
      <.active_filter_badges
        filters={Enum.reject(@filters, & &1.config.always_on)}
        editing_id={@editing_filter_id}
        myself={@myself}
      />

      <%!-- Add filter button --%>
      <.add_filter_button
        config={@config}
        active_fields={MapSet.new(@filters, & &1.field)}
        show_picker={@show_field_picker}
        myself={@myself}
      />

      <%!-- Clear all (when filters active) --%>
      <button
        :if={length(@filters) > 0}
        phx-click="clear_all"
        phx-target={@myself}
        class="btn btn-ghost btn-xs"
      >
        Clear all
      </button>
    </div>
    """
  end
end
```

### 4.4 UI Interaction Model

The user experience follows the Linear/Notion pattern:

**Adding a filter:**
1. User clicks `+ Add filter` button
2. Dropdown shows available fields (grouped by type, searchable for long lists)
3. User clicks a field name (e.g., "Status")
4. A filter badge appears inline, immediately opening its editor
5. User selects operator (if applicable) and enters value
6. On blur/enter/select, filter is applied, URL updates

**Editing an existing filter:**
1. User clicks on a filter badge (e.g., `Status = active`)
2. Inline popover opens with operator selector + value input
3. Changes apply on interaction (debounced for text)

**Removing a filter:**
1. User clicks the `×` on a filter badge
2. Filter removed, URL updates

**Sharing:**
1. URL always reflects current filter state
2. Copying the URL and sending to another user reproduces the exact filter set

### 4.5 Debouncing Strategy

Text and number inputs use LiveView's built-in `phx-debounce`:

```elixir
# In filter input templates
<input
  type="text"
  value={@filter.value}
  phx-change="update_filter"
  phx-debounce="300"
  phx-target={@myself}
  name="value"
  class="input input-sm input-bordered"
/>
```

Select, multi-select, boolean, and date inputs apply immediately on change (no debounce needed).

---

## Part 5: LiveView Integration API

### 5.1 Convenience Functions

```elixir
defmodule LiveFilter do
  # ... (filter type builders from Part 1.5) ...

  @doc """
  Initialize LiveFilter state in a LiveView socket.
  Call in mount/3 after parsing params.
  """
  def init(socket, config, initial_filters \\ []) do
    assign(socket, :live_filter, %{
      config: config,
      filters: initial_filters,
      id: "live-filter-#{System.unique_integer([:positive])}"
    })
  end

  @doc """
  Parse URL params into filter state and remaining params.
  Call in mount/3 to hydrate from shareable URL.
  """
  def from_params(params, config) do
    LiveFilter.Params.Parser.from_params(params, config)
  end

  @doc """
  Convenience component that delegates to LiveFilter.Bar.
  """
  def bar(assigns) do
    ~H"""
    <.live_component
      module={LiveFilter.Bar}
      id={@filter.id}
      config={@filter.config}
      filters={@filter.filters}
      on_change={@filter.on_change}
    />
    """
  end
end
```

### 5.2 Full LiveView Example

```elixir
defmodule MyAppWeb.OrdersLive do
  use MyAppWeb, :live_view

  alias MyApp.{Repo, Order}
  import Ecto.Query

  @filter_config [
    LiveFilter.text(:reference, label: "Reference", always_on: true),
    LiveFilter.select(:status, label: "Status",
      options: ["pending", "confirmed", "shipped", "delivered", "cancelled"]),
    LiveFilter.multi_select(:tags, label: "Tags",
      options_fn: fn -> MyApp.Tags.list_tag_names() end),
    LiveFilter.number(:total, label: "Order Total",
      operators: [:gte, :lte, :eq, :gt, :lt]),
    LiveFilter.date_range(:inserted_at, label: "Created Date"),
    LiveFilter.boolean(:urgent, label: "Urgent Only"),
    LiveFilter.text(:customer_name, label: "Customer",
      custom_param: "search",
      operators: [:ilike])
  ]

  @impl true
  def mount(params, _session, socket) do
    {filters, _remaining} = LiveFilter.from_params(params, @filter_config)

    socket =
      socket
      |> assign(:page_title, "Orders")
      |> assign(:filter_config, @filter_config)
      |> assign(:active_filters, filters)
      |> load_orders()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {filters, _remaining} = LiveFilter.from_params(params, @filter_config)

    socket =
      socket
      |> assign(:active_filters, filters)
      |> load_orders()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:live_filter, :updated, query_params}, socket) do
    {:noreply, push_patch(socket, to: ~p"/orders?#{query_params}")}
  end

  defp load_orders(socket) do
    orders =
      Order
      |> where([o], o.tenant_id == ^socket.assigns.current_tenant.id)
      |> LiveFilter.QueryBuilder.apply(socket.assigns.active_filters, adapter: :postgres)
      |> order_by([o], desc: o.inserted_at)
      |> limit(50)
      |> Repo.all()

    assign(socket, :orders, orders)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.live_component
        module={LiveFilter.Bar}
        id="orders-filter"
        config={@filter_config}
        filters={@active_filters}
        on_change={fn params -> send(self(), {:live_filter, :updated, params}) end}
      />

      <.table id="orders-table" rows={@orders}>
        <:col :let={order} label="Reference"><%= order.reference %></:col>
        <:col :let={order} label="Status"><%= order.status %></:col>
        <:col :let={order} label="Total"><%= order.total %></:col>
        <:col :let={order} label="Created"><%= order.inserted_at %></:col>
      </.table>
    </div>
    """
  end
end
```

---

## Part 6: Saved Filter Sets (Views)

### 6.1 Concept

Like Linear's "Views" or Airtable's saved filters — users can save a combination of active filters as a named set and recall them later.

### 6.2 FilterSet Schema

```elixir
defmodule LiveFilter.FilterSet do
  @moduledoc """
  A saved combination of filters, serialized as PostgREST query params.
  Persistence is the host app's responsibility.
  """

  @type t :: %__MODULE__{
    id: String.t(),
    name: String.t(),
    params: map(),           # Serialized PostgREST params
    resource: String.t(),    # Which list view (e.g., "orders")
    user_id: term(),         # Owner
    shared: boolean(),       # Visible to others?
    pinned: boolean(),       # Show as tab?
    inserted_at: DateTime.t()
  }

  defstruct [:id, :name, :params, :resource, :user_id,
             shared: false, pinned: false, inserted_at: nil]
end
```

### 6.3 FilterSet Persistence Behavior

```elixir
defmodule LiveFilter.FilterSet.Store do
  @moduledoc """
  Behavior for persisting filter sets.
  Implement in your app to enable saved views.
  """

  @callback list_filter_sets(resource :: String.t(), user_id :: term()) :: [LiveFilter.FilterSet.t()]
  @callback save_filter_set(LiveFilter.FilterSet.t()) :: {:ok, LiveFilter.FilterSet.t()} | {:error, term()}
  @callback delete_filter_set(id :: String.t()) :: :ok | {:error, term()}
end
```

Host apps implement this with their own Ecto schema or even simple JSON storage. LiveFilter provides the UI for save/load/delete.

### 6.4 FilterSet UI

Saved filter sets appear as tabs or a dropdown above the filter bar:

```
┌─────────────────────────────────────────────────────────────┐
│  [All Orders]  [Pending Review]  [This Month]  [+ Save]    │
├─────────────────────────────────────────────────────────────┤
│  + Add filter  │ Status = active  │ Total ≥ 100  │ Clear   │
└─────────────────────────────────────────────────────────────┘
```

Clicking a saved view tab applies its params via `push_patch`, same as sharing a URL.

---

## Part 7: Operator Reference

### 7.1 Operators by Filter Type

| Filter Type | Default Op | Available Operators | PostgREST Param |
|------------|-----------|-------------------|-----------------|
| `:text` | `:ilike` | `ilike`, `like`, `eq`, `neq` | `name=ilike.*smith*` |
| `:number` | `:eq` | `eq`, `neq`, `gt`, `gte`, `lt`, `lte` | `total=gte.100` |
| `:select` | `:eq` | `eq`, `neq` | `status=eq.active` |
| `:multi_select` | `:in` | `in` | `status=in.(a,b,c)` |
| `:date` | `:eq` | `eq`, `gt`, `gte`, `lt`, `lte` | `due=gte.2024-01-01` |
| `:date_range` | `:gte_lte` | `gte_lte` (compound) | `created=gte.2024-01-01&created=lte.2024-02-01` |
| `:datetime` | `:gte` | `eq`, `gt`, `gte`, `lt`, `lte` | `updated=gte.2024-01-01T00:00:00Z` |
| `:boolean` | `:is` | `is` | `urgent=is.true` |

### 7.2 Operator Display Labels

```elixir
defmodule LiveFilter.Operators do
  @labels %{
    eq: "is",
    neq: "is not",
    gt: "greater than",
    gte: "at least",
    lt: "less than",
    lte: "at most",
    like: "contains (case-sensitive)",
    ilike: "contains",
    in: "is any of",
    is: "is",
    cs: "contains",
    cd: "contained in",
    fts: "matches",
    gte_lte: "between"
  }

  def label(op), do: Map.get(@labels, op, to_string(op))

  def options_for_type(:text), do: [{:ilike, "contains"}, {:eq, "is"}, {:neq, "is not"}, {:like, "contains (exact)"}]
  def options_for_type(:number), do: [{:eq, "="}, {:neq, "≠"}, {:gt, ">"}, {:gte, "≥"}, {:lt, "<"}, {:lte, "≤"}]
  def options_for_type(:select), do: [{:eq, "is"}, {:neq, "is not"}]
  def options_for_type(:date), do: [{:eq, "is"}, {:gte, "on or after"}, {:lte, "on or before"}, {:gt, "after"}, {:lt, "before"}]
  def options_for_type(_), do: []
end
```

---

## Part 8: Project Structure

```
live_filter/
├── lib/
│   ├── live_filter.ex                        # Public API (type builders, init, from_params)
│   └── live_filter/
│       ├── types.ex                          # Type definitions
│       ├── filter_config.ex                  # FilterConfig struct
│       ├── filter.ex                         # Filter (active filter instance) struct
│       ├── operators.ex                      # Operator labels and per-type mappings
│       │
│       ├── params/                           # Param Layer
│       │   ├── serializer.ex                 # Filter state → PostgREST params
│       │   ├── parser.ex                     # PostgREST params → filter state
│       │   └── validator.ex                  # Safety validation
│       │
│       ├── query_builder/                    # Query Layer
│       │   ├── query_builder.ex              # Public API (apply/3, apply_raw/3)
│       │   ├── adapter.ex                    # Adapter behavior
│       │   └── adapters/
│       │       └── postgres.ex               # PostgreSQL adapter
│       │
│       ├── components/                       # UI Layer (LiveComponents)
│       │   ├── bar.ex                        # Main filter bar component
│       │   ├── active_filters.ex             # Active filter badge row
│       │   ├── filter_badge.ex               # Single filter badge
│       │   ├── add_filter_dropdown.ex        # "+ Add filter" dropdown
│       │   ├── field_picker.ex               # Field selection list
│       │   ├── filter_editor.ex              # Inline value editor
│       │   └── inputs/                       # Per-type input components
│       │       ├── text.ex
│       │       ├── number.ex
│       │       ├── select.ex
│       │       ├── multi_select.ex
│       │       ├── date.ex
│       │       ├── date_range.ex
│       │       ├── datetime.ex
│       │       └── boolean.ex
│       │
│       └── filter_set/                       # Saved Views (optional)
│           ├── filter_set.ex                 # FilterSet struct
│           └── store.ex                      # Persistence behavior
│
├── test/
│   ├── live_filter_test.exs
│   └── live_filter/
│       ├── params/
│       │   ├── serializer_test.exs
│       │   ├── parser_test.exs
│       │   └── validator_test.exs
│       ├── query_builder/
│       │   ├── query_builder_test.exs
│       │   └── adapters/
│       │       └── postgres_test.exs
│       └── components/
│           └── bar_test.exs
│
├── mix.exs
└── README.md
```

---

## Part 9: Implementation Phases

### Phase 1: Core Foundation
- `FilterConfig` and `Filter` structs
- Operator definitions and per-type mappings
- Builder functions (`LiveFilter.text/2`, `LiveFilter.select/2`, etc.)

### Phase 2: Param Layer
- Serializer (filter state → PostgREST query params)
- Parser (PostgREST query params → filter state)
- Validator (safety checks)
- Round-trip property tests (serialize → parse → serialize = identity)

### Phase 3: Query Builder
- Adapter behavior
- Postgres adapter with all standard operators
- `QueryBuilder.apply/3` public API
- Integration tests with Ecto sandbox

### Phase 4: UI Components (MVP)
- `LiveFilter.Bar` LiveComponent
- `AddFilterDropdown` with field picker
- `FilterBadge` with remove button
- `FilterEditor` with per-type inputs (text, select, boolean first)
- DaisyUI styling with `daisy_ui_components`

### Phase 5: UI Components (Complete)
- Multi-select input with checkbox dropdown
- Date and date range pickers
- DateTime input
- Number input with operator selector
- Debounced text input

### Phase 6: URL Integration
- `push_patch` on filter change
- `from_params` hydration in `handle_params`
- Full shareable URL round-trip

### Phase 7: Saved Filter Sets
- `FilterSet` struct and `Store` behavior
- Save/load/delete UI
- Tab bar for pinned views

### Phase 8: Polish & Testing
- Accessibility (ARIA labels, keyboard navigation)
- Empty states and loading indicators
- Property-based testing (serializer ↔ parser round-trip)
- Visual regression with Storybook (optional)

---

## Part 10: Comparison with Alternatives

| Feature | LiveFilter | react-admin StackedFilters | Backpacker (Elixir) | Flop (Elixir) |
|---------|-----------|--------------------------|--------------------|----|
| PostgREST-compatible params | ✅ | ❌ (custom format) | ❌ | ❌ |
| Shareable filter URLs | ✅ | ❌ | Partial | ✅ |
| LiveView native | ✅ | N/A (React) | ✅ | ✅ |
| Operator selection UI | ✅ | ✅ | ❌ | ❌ |
| Composable filter types | ✅ | ✅ | Limited | Limited |
| Saved filter sets | ✅ | ❌ | ❌ | ❌ |
| Pluggable query backend | ✅ (adapter) | ✅ (data provider) | ❌ | ❌ |
| DaisyUI styled | ✅ | N/A (MUI) | ❌ | ❌ |
| ExRest integration | ✅ | N/A | ❌ | ❌ |

### When to Use LiveFilter

- Building Phoenix LiveView apps with list/table views
- Want Linear/Notion-style composable filter UIs
- Need PostgREST-compatible URL params (ExRest/Supabase ecosystem)
- Want shareable filtered view links
- Using DaisyUI for styling

---

## Part 11: Dependencies

```elixir
defp deps do
  [
    {:phoenix_live_view, "~> 1.0"},
    {:ecto, "~> 3.10"},
    {:ecto_sql, "~> 3.10"},             # For query building
    {:daisy_ui_components, "~> 0.9"},    # DaisyUI LiveView components
    {:jason, "~> 1.4"},                  # JSON for filter set serialization

    # Dev/Test
    {:ex_doc, "~> 0.30", only: :dev},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:stream_data, "~> 1.0", only: :test}  # Property-based testing
  ]
end
```

---

## Part 12: Open Questions

1. **Logical grouping (AND/OR)?** Should LiveFilter support OR groups in the UI? PostgREST supports `or=(status.eq.a,status.eq.b)` but the UI complexity is significant. Linear keeps it simple (AND only) which covers 90% of cases. Start AND-only, add OR as a later phase?

2. **Nested resource filters?** PostgREST supports `posts.status=eq.active` for filtering on associations. Worth supporting in the UI, or leave to `handle_param` custom params?

3. **Sort integration?** Should LiveFilter also handle `order=created_at.desc` params? Or keep sorting as a separate concern (clickable column headers)?

4. **Pagination integration?** Same question for `limit` and `offset` params. Probably separate.

5. **Server-side options loading?** For multi-select with many options, should LiveFilter support async option loading (search-as-you-type)? This adds complexity but is essential for reference fields.

6. **Custom filter type extensibility?** Should there be a behavior for defining new filter types (e.g., a "location radius" filter)? Or is `custom_param` + `handle_param/4` sufficient?

7. **Library name?** `LiveFilter`, `PhxFilter`, `ExFilter`, `FilterKit`?

---

## Appendix A: ExRest Shared Param Format

The canonical format shared between LiveFilter and ExRest:

```
# Comparison
?field=eq.value         → field = value
?field=neq.value        → field <> value
?field=gt.value         → field > value
?field=gte.value        → field >= value
?field=lt.value         → field < value
?field=lte.value        → field <= value

# Pattern matching
?field=like.*value*     → field LIKE '%value%'
?field=ilike.*value*    → field ILIKE '%value%'

# Lists
?field=in.(a,b,c)       → field IN ('a', 'b', 'c')

# Null/Boolean
?field=is.null          → field IS NULL
?field=is.true          → field = TRUE
?field=is.false         → field = FALSE

# Arrays
?field=cs.{a,b}         → field @> '{a,b}'
?field=cd.{a,b}         → field <@ '{a,b}'

# Full-text search
?field=fts.search+terms → field @@ plainto_tsquery('search terms')

# Ordering (not part of LiveFilter, but passed through)
?order=created_at.desc.nullslast

# Pagination (not part of LiveFilter, but passed through)
?limit=50&offset=100
```

## Appendix B: Filter Badge Display Format

How active filters are displayed as badges:

| Filter Type | Badge Display Example |
|---|---|
| Text (ilike) | `Reference contains "ORD-123"` |
| Text (eq) | `Reference is "ORD-123"` |
| Number (gte) | `Total ≥ 100` |
| Select (eq) | `Status is active` |
| Multi-select (in) | `Tags is any of: urgent, priority` |
| Date (gte) | `Created on or after Jan 1, 2024` |
| Date range | `Created between Jan 1 – Feb 1, 2024` |
| Boolean (is true) | `Urgent` |
| Boolean (is false) | `Not urgent` |
