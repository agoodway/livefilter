defmodule LiveFilter do
  @moduledoc """
  Composable filter UI library for Phoenix LiveView.

  Provides builder functions for defining filterable fields that produce
  `LiveFilter.FilterConfig` structs.

  ## Example

      filters = [
        LiveFilter.text(:search, label: "Search", always_on: true, custom_param: "search"),
        LiveFilter.select(:status, label: "Status", options: ~w(pending active shipped)),
        LiveFilter.multi_select(:tags, label: "Tags", options: ~w(urgent bug feature)),
        LiveFilter.date_range(:inserted_at, label: "Created"),
        LiveFilter.boolean(:urgent, label: "Urgent")
      ]
  """

  alias LiveFilter.{Filter, FilterConfig, Pagination, Params.Parser, Params.Serializer, SortField}

  use Phoenix.Component

  @max_offset 100_000

  @doc """
  Creates a text filter config.

  Default operators: `[:ilike, :eq, :neq, :like]`, default: `:ilike`.
  """
  @spec text(atom(), keyword()) :: FilterConfig.t()
  def text(field, opts \\ []) do
    build_config(field, :text, opts,
      operators: [:ilike, :eq, :neq, :like],
      default_operator: :ilike
    )
  end

  @doc """
  Creates a number filter config.

  Default operators: `[:eq, :neq, :gt, :gte, :lt, :lte]`, default: `:eq`.
  """
  @spec number(atom(), keyword()) :: FilterConfig.t()
  def number(field, opts \\ []) do
    build_config(field, :number, opts,
      operators: [:eq, :neq, :gt, :gte, :lt, :lte],
      default_operator: :eq
    )
  end

  @doc """
  Creates a single-select filter config.

  Default operators: `[:eq, :neq]`, default: `:eq`.
  Requires `:options` or `:options_fn`.
  """
  @spec select(atom(), keyword()) :: FilterConfig.t()
  def select(field, opts \\ []) do
    build_config(field, :select, opts,
      operators: [:eq, :neq],
      default_operator: :eq
    )
  end

  @doc """
  Creates a multi-select filter config.

  Default operators: `[:cs, :ov]`, default: `:cs`.
  Requires `:options` or `:options_fn`.

  Note: Uses array containment operators for Postgres array columns:
  - `:cs` - contains (`@>`) - array contains all selected values
  - `:ov` - overlaps (`&&`) - array contains any of the selected values
  """
  @spec multi_select(atom(), keyword()) :: FilterConfig.t()
  def multi_select(field, opts \\ []) do
    build_config(field, :multi_select, opts,
      operators: [:cs, :ov],
      default_operator: :ov
    )
  end

  @doc """
  Creates a date filter config.

  Default operators: `[:eq, :gt, :gte, :lt, :lte]`, default: `:eq`.
  """
  @spec date(atom(), keyword()) :: FilterConfig.t()
  def date(field, opts \\ []) do
    build_config(field, :date, opts,
      operators: [:eq, :gt, :gte, :lt, :lte],
      default_operator: :eq
    )
  end

  @doc """
  Creates a date range filter config.

  Default operators: `[:gte_lte]`, default: `:gte_lte`.

  Use this for `:date` schema fields. For `:utc_datetime` or `:utc_datetime_usec`
  fields, use `datetime_range/2` instead.
  """
  @spec date_range(atom(), keyword()) :: FilterConfig.t()
  def date_range(field, opts \\ []) do
    build_config(field, :date_range, opts,
      operators: [:gte_lte],
      default_operator: :gte_lte
    )
  end

  @doc """
  Creates a datetime range filter config.

  Default operators: `[:gte_lte]`, default: `:gte_lte`.

  Similar to `date_range/2` but generates full ISO8601 datetime values with
  start-of-day (00:00:00Z) and end-of-day (23:59:59Z) times. Use this for
  `:utc_datetime` or `:utc_datetime_usec` schema fields.
  """
  @spec datetime_range(atom(), keyword()) :: FilterConfig.t()
  def datetime_range(field, opts \\ []) do
    build_config(field, :datetime_range, opts,
      operators: [:gte_lte],
      default_operator: :gte_lte
    )
  end

  @doc """
  Creates a datetime filter config.

  Default operators: `[:eq, :gt, :gte, :lt, :lte]`, default: `:eq`.

  ## Options

  - `:time_format` - Time display format: `:twelve_hour` (default) or `:twenty_four_hour`
  - `:minute_step` - Minute increment step: 1 (default), 5, 15, or 30
  """
  @spec datetime(atom(), keyword()) :: FilterConfig.t()
  def datetime(field, opts \\ []) do
    build_config(field, :datetime, opts,
      operators: [:eq, :gt, :gte, :lt, :lte],
      default_operator: :eq,
      time_format: Keyword.get(opts, :time_format, :twelve_hour),
      minute_step: Keyword.get(opts, :minute_step, 1)
    )
  end

  @doc """
  Creates a boolean filter config.

  Default operators: `[:is]`, default: `:is`.

  ## Options

  - `:true_label` - Label for true state (default: "Yes")
  - `:false_label` - Label for false state (default: "No")
  - `:any_label` - Label for null/any state (default: "Any")
  - `:nullable` - Enable 3-state (true/false/any) mode (default: false)
  """
  @spec boolean(atom(), keyword()) :: FilterConfig.t()
  def boolean(field, opts \\ []) do
    build_config(field, :boolean, opts,
      operators: [:is],
      default_operator: :is,
      true_label: Keyword.get(opts, :true_label, "Yes"),
      false_label: Keyword.get(opts, :false_label, "No"),
      any_label: Keyword.get(opts, :any_label, "Any"),
      nullable: Keyword.get(opts, :nullable, false)
    )
  end

  @doc """
  Creates a radio group filter config.

  Default operators: `[:eq]`, default: `:eq`.
  Requires `:options` or `:options_fn`.

  ## Options

  - `:style` - Display style: `:pills` (default) or `:radios`
  - `:inline_threshold` - Max options to show inline as pills (default: 4)
  - `:options` - List of options (required)
  """
  @spec radio_group(atom(), keyword()) :: FilterConfig.t()
  def radio_group(field, opts \\ []) do
    build_config(field, :radio_group, opts,
      operators: [:eq],
      default_operator: :eq,
      style: Keyword.get(opts, :style, :pills),
      inline_threshold: Keyword.get(opts, :inline_threshold, 4)
    )
  end

  @doc """
  Creates an async select filter config for search-as-you-type selection.

  Default operators: `[:eq]`, default: `:eq`.

  Requires `:search_fn` and `:load_label_fn` callbacks.

  ## Callbacks

  - `:search_fn` - `fn(query, context) -> [{value, label}]` — called when user types in the dropdown
  - `:load_label_fn` - `fn(value, context) -> {:ok, label} | :error` — called to resolve display label from a stored value (e.g., on URL reload)

  ## Options

  - `:min_chars` - Minimum characters before searching (default: 1)
  - `:debounce` - Debounce delay in ms (default: 200)
  - `:placeholder` - Search input placeholder (default: "Search...")
  - `:empty_message` - Message when no results found (default: "No results found")
  """
  @spec async_select(atom(), keyword()) :: FilterConfig.t()
  def async_select(field, opts \\ []) do
    validate_async_select_options!(field, opts)

    config =
      build_config(field, :async_select, opts,
        operators: [:eq],
        default_operator: :eq
      )

    %{
      config
      | search_fn: Keyword.fetch!(opts, :search_fn),
        load_label_fn: Keyword.fetch!(opts, :load_label_fn),
        min_chars: Keyword.get(opts, :min_chars, 1),
        debounce: Keyword.get(opts, :debounce, 200),
        empty_message: Keyword.get(opts, :empty_message, "No results found")
    }
  end

  defp validate_async_select_options!(field, opts) do
    if Keyword.get(opts, :always_on, false) do
      raise ArgumentError, "async_select filter :#{field} does not support always_on: true"
    end

    unless Keyword.has_key?(opts, :search_fn) do
      raise ArgumentError, "async_select filter :#{field} requires :search_fn"
    end

    unless Keyword.has_key?(opts, :load_label_fn) do
      raise ArgumentError, "async_select filter :#{field} requires :load_label_fn"
    end
  end

  @doc """
  Builds a `LiveFilter.SortField` declaration for the sort UI + parse allow-list.

  ## Options
    * `:label` - display label (default: capitalized field name)
    * `:query_field` - the DB column to order by (default: the field name)
    * `:default_direction` - first-click direction, `:asc` (default) or `:desc`
    * `:nulls` - default nulls placement: `nil` (default), `:first`, or `:last`
  """
  @spec sort_field(atom(), keyword()) :: SortField.t()
  def sort_field(field, opts \\ []) when is_atom(field) do
    direction = Keyword.get(opts, :default_direction, :asc)

    unless direction in [:asc, :desc] do
      raise ArgumentError, "sort_field :#{field} default_direction must be :asc or :desc"
    end

    %SortField{
      field: field,
      label: build_label(field, opts),
      query_field: Keyword.get(opts, :query_field),
      default_direction: direction,
      nulls: Keyword.get(opts, :nulls)
    }
  end

  # --- LiveView Integration ---

  @doc """
  Initializes LiveFilter state on a socket.

  Assigns `:livefilter` with config, filters, and a unique ID.
  Accepts an optional `context:` keyword that is stored and passed to async_select callbacks.
  """
  @spec init(Phoenix.LiveView.Socket.t(), [FilterConfig.t()], [Filter.t()], keyword()) ::
          Phoenix.LiveView.Socket.t()
  def init(socket, config, filters \\ [], opts \\ []) do
    context = Keyword.get(opts, :context, %{})

    # Preserve existing ID across push_patch to maintain input focus
    existing_id = get_in(socket.assigns, [:livefilter, :id])

    id =
      existing_id ||
        "live-filter-" <> (:crypto.strong_rand_bytes(4) |> Base.url_encode64(padding: false))

    assign(socket, :livefilter, %{
      config: config,
      filters: filters,
      id: id,
      context: context
    })
  end

  @doc """
  Parses URL params into filter state using the provided config.

  Returns `{filters, remaining_params}`.
  """
  @spec from_params(map(), [FilterConfig.t()]) :: {[Filter.t()], map()}
  def from_params(params, config) do
    Parser.from_params(params, config)
  end

  @doc """
  Parses pagination from URL params using PostgREST `limit`/`offset` parameters.

  Returns `{pagination, remaining_params}`.

  ## Options

    * `:default_limit` - Default items per page (default: 25)
    * `:max_limit` - Maximum allowed limit value (default: 100)
    * `:limit_options` - Available per-page options for UI dropdown (default: [10, 25, 50, 100])

  ## Example

      {pagination, remaining} = LiveFilter.pagination_from_params(params, default_limit: 25)
      # pagination.limit => 25
      # pagination.offset => 0

      # With URL ?limit=50&offset=100
      {pagination, remaining} = LiveFilter.pagination_from_params(%{"limit" => "50", "offset" => "100"})
      # pagination.limit => 50
      # pagination.offset => 100
  """
  @spec pagination_from_params(map(), keyword()) :: {Pagination.t(), map()}
  def pagination_from_params(params, opts \\ []) do
    default_limit = Keyword.get(opts, :default_limit, 25)
    max_limit = Keyword.get(opts, :max_limit, 100)
    limit_options = Keyword.get(opts, :limit_options, [10, 25, 50, 100])
    max_offset = Keyword.get(opts, :max_offset, @max_offset)

    pagination = %Pagination{
      limit: parse_limit(params, default_limit, max_limit),
      offset: parse_offset(params, max_offset),
      limit_options: limit_options,
      max_limit: max_limit
    }

    remaining = extract_remaining_params(params)

    {pagination, remaining}
  end

  defp parse_limit(params, default_limit, max_limit) do
    params
    |> Map.get("limit")
    |> parse_positive_int(default_limit)
    |> min(max_limit)
  end

  defp parse_offset(params, max_offset) do
    params
    |> Map.get("offset")
    |> parse_non_negative_int(0)
    |> min(max_offset)
  end

  defp extract_remaining_params(params) do
    params
    |> Map.delete("limit")
    |> Map.delete("offset")
  end

  defp parse_positive_int(nil, default), do: default

  defp parse_positive_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end

  defp parse_positive_int(val, _default) when is_integer(val) and val > 0, do: val
  defp parse_positive_int(_, default), do: default

  defp parse_non_negative_int(nil, default), do: default

  defp parse_non_negative_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, ""} when int >= 0 -> int
      _ -> default
    end
  end

  defp parse_non_negative_int(val, _default) when is_integer(val) and val >= 0, do: val
  defp parse_non_negative_int(_, default), do: default

  @doc """
  Parses the PostgREST `order=` param into a `LiveFilter.Sort`, validated against
  the given `sortable_fields` (a list of `LiveFilter.SortField`).

  Returns `{sort, remaining_params}`. Unknown fields and malformed tokens are
  dropped (allow-list = injection + dynamic-column safety). When `order` is
  absent or every entry is invalid, `opts[:default]` (a `%LiveFilter.Sort{}`) is
  used, defaulting to an empty sort.

  ## Example

      {sort, remaining} =
        LiveFilter.sort_from_params(params, sortable_fields, default: default_sort())
  """
  @spec sort_from_params(map(), [SortField.t()], keyword()) :: {LiveFilter.Sort.t(), map()}
  def sort_from_params(params, sortable_fields, opts \\ []) do
    default = Keyword.get(opts, :default, %LiveFilter.Sort{})
    remaining = Map.delete(params, "order")

    case Map.get(params, "order") do
      order when is_binary(order) and order != "" ->
        by_field = Map.new(sortable_fields, &{Atom.to_string(&1.field), &1})

        entries =
          order
          |> String.split(",", trim: true)
          |> Enum.map(&LiveFilter.Sort.from_token(&1, by_field))
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq_by(& &1.field)

        sort = if entries == [], do: default, else: %LiveFilter.Sort{entries: entries}
        {sort, remaining}

      _ ->
        {default, remaining}
    end
  end

  @doc ~S"""
  Builds a path with raw (non-encoded) query string from a params map.

  Use this instead of `~p"/path?#{params}"` to avoid percent-encoding
  special characters like `{`, `}`, and `,`.

  ## Example

      # In handle_info:
      path = LiveFilter.to_path("/tasks", all_params)
      {:noreply, push_patch(socket, to: path)}

      # Produces: /tasks?tags=ov.{testing,bug}
      # Instead of: /tasks?tags=ov.%7Btesting%2Cbug%7D
  """
  @spec to_path(String.t(), map()) :: String.t()
  defdelegate to_path(base_path, params), to: Serializer

  @doc """
  Convenience function component that renders `LiveFilter.Bar`.

  ## Options

  - `:mode` - Filter display mode: `:basic` (default) or `:command`
  - `:theme` - Theme preset: `:default`, `:minimal`, or `:bordered`
  - `:variant` - Chip border style: `:outline` (default), `:ghost`, `:soft`, or custom class string

  ## Example

      <LiveFilter.bar filter={@livefilter} />
      <LiveFilter.bar filter={@livefilter} mode={:command} />
      <LiveFilter.bar filter={@livefilter} mode={:command} theme={:bordered} />
      <LiveFilter.bar filter={@livefilter} variant={:ghost} />
  """
  attr(:filter, :map, required: true)
  attr(:mode, :atom, default: :basic)
  attr(:theme, :atom, default: :default)

  attr(:variant, :atom,
    default: :outline,
    doc: "Chip border style: :outline (default), :ghost, or :soft"
  )

  def bar(assigns) do
    ~H"""
    <.live_component module={LiveFilter.Bar} id={@filter.id} filter={@filter} mode={@mode} theme={@theme} variant={@variant} />
    """
  end

  @doc """
  Convenience function component that renders `LiveFilter.Paginator`.

  ## Example

      <LiveFilter.paginator pagination={@pagination} />
      <LiveFilter.paginator pagination={@pagination} class="mt-4" />
  """
  attr(:pagination, Pagination, required: true)
  attr(:class, :string, default: "")

  def paginator(assigns) do
    ~H"""
    <.live_component module={LiveFilter.Paginator} id="live-filter-paginator" pagination={@pagination} class={@class} />
    """
  end

  @doc """
  Convenience wrapper for `LiveFilter.SortComponents.sort_header/1`.
  """
  attr(:field, :atom, required: true)
  attr(:label, :string, required: true)
  attr(:sort, LiveFilter.Sort, required: true)
  attr(:sortable_fields, :list, default: [])
  attr(:event, :string, default: "lf_sort")
  attr(:target, :any, default: nil)
  attr(:class, :string, default: nil)
  slot(:inner_block)

  def sort_header(assigns), do: LiveFilter.SortComponents.sort_header(assigns)

  @doc """
  Convenience wrapper for `LiveFilter.SortComponents.sort_menu/1`.
  """
  attr(:sortable_fields, :list, required: true)
  attr(:sort, LiveFilter.Sort, required: true)
  attr(:id, :string, default: "lf-sort-menu")
  attr(:event, :string, default: "lf_sort_to")
  attr(:target, :any, default: nil)
  attr(:class, :string, default: nil)

  def sort_menu(assigns), do: LiveFilter.SortComponents.sort_menu(assigns)

  defp build_config(field, type, opts, defaults) do
    validate_options!(field, type, opts)

    default_visible = Keyword.get(opts, :default_visible, false)
    removable_default = not default_visible

    %FilterConfig{
      field: field,
      type: type,
      label: build_label(field, opts),
      operators: Keyword.get(opts, :operators, defaults[:operators]),
      default_operator: Keyword.get(opts, :default_operator, defaults[:default_operator]),
      options: Keyword.get(opts, :options),
      options_fn: Keyword.get(opts, :options_fn),
      placeholder: Keyword.get(opts, :placeholder),
      always_on: Keyword.get(opts, :always_on, false),
      default_visible: default_visible,
      default_value: Keyword.get(opts, :default_value),
      query_field: Keyword.get(opts, :query_field),
      custom_param: Keyword.get(opts, :custom_param),
      input_component: Keyword.get(opts, :input_component),
      hide_label: Keyword.get(opts, :hide_label, false),
      icon: Keyword.get(opts, :icon),
      theme: Keyword.get(opts, :theme),
      mode: Keyword.get(opts, :mode),
      removable: Keyword.get(opts, :removable, removable_default),
      search_threshold: Keyword.get(opts, :search_threshold),
      date_presets: Keyword.get(opts, :date_presets),
      true_label: defaults[:true_label] || "Yes",
      false_label: defaults[:false_label] || "No",
      any_label: defaults[:any_label] || "Any",
      nullable: defaults[:nullable] || false,
      style: defaults[:style] || :pills,
      inline_threshold: defaults[:inline_threshold] || 4,
      time_format: defaults[:time_format] || :twelve_hour,
      minute_step: defaults[:minute_step] || 1
    }
  end

  defp validate_options!(field, type, opts) when type in [:select, :multi_select, :radio_group] do
    has_options = Keyword.has_key?(opts, :options) or Keyword.has_key?(opts, :options_fn)

    unless has_options do
      raise ArgumentError, "#{type} filter :#{field} requires either :options or :options_fn"
    end
  end

  defp validate_options!(_field, _type, _opts), do: :ok

  defp build_label(field, opts) do
    Keyword.get_lazy(opts, :label, fn ->
      field |> Atom.to_string() |> String.capitalize()
    end)
  end
end
