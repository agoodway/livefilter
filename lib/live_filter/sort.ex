defmodule LiveFilter.Sort do
  @moduledoc """
  Sort state — a list of `LiveFilter.Sort.Entry` ordered by priority.

  An orthogonal, URL-shareable concern (like `LiveFilter.Pagination`). The list
  is multi-column ready even though the bundled UI sets a single active sort.
  `entries: []` means "no explicit sort" — the consumer's default ordering applies.

  ## Example

      {sort, remaining} = LiveFilter.sort_from_params(params, sortable_fields)
      LiveFilter.Sort.to_params(sort)            # => %{"order" => "clicks.desc"}
      LiveFilter.Sort.direction_for(sort, :clicks) # => :desc
  """

  alias LiveFilter.Sort
  alias LiveFilter.Sort.Entry

  @type t :: %__MODULE__{entries: [Entry.t()]}
  defstruct entries: []

  defmodule Entry do
    @moduledoc "One sort rule: a public field, direction, optional DB column + nulls placement."
    @type direction :: :asc | :desc
    @type nulls :: nil | :first | :last
    @type t :: %__MODULE__{
            field: atom(),
            direction: direction(),
            query_field: atom() | nil,
            nulls: nulls()
          }
    defstruct [:field, :direction, query_field: nil, nulls: nil]
  end

  @doc "Direction of `field` in the current sort, or `nil` if it is not sorted."
  @spec direction_for(t(), atom()) :: Entry.direction() | nil
  def direction_for(%Sort{entries: entries}, field) do
    Enum.find_value(entries, fn %Entry{field: f, direction: d} -> if f == field, do: d end)
  end

  @doc """
  Tri-state single-sort toggle for a header click.

  Cycle: `none -> default_direction -> opposite -> none`. Replaces any other
  active sort (single-sort UI).

  ## Options
    * `:default_direction` - first-click direction (default `:asc`)
    * `:nulls` - nulls placement to carry onto the new entry (default `nil`)
  """
  @spec toggle(t(), atom()) :: t()
  def toggle(%Sort{} = sort, field), do: toggle(sort, field, [])

  @doc """
  Tri-state toggle that reads the field's `default_direction`/`nulls` from a
  `LiveFilter.SortField` list. A field not present in the list is treated as
  not sortable and the sort is returned unchanged (no-op).
  """
  @spec toggle(t(), atom(), [LiveFilter.SortField.t()] | keyword()) :: t()
  def toggle(%Sort{} = sort, field, [%LiveFilter.SortField{} | _] = sortable_fields) do
    case Enum.find(sortable_fields, &(&1.field == field)) do
      %LiveFilter.SortField{default_direction: dir, nulls: nulls} ->
        toggle(sort, field, default_direction: dir, nulls: nulls)

      nil ->
        sort
    end
  end

  def toggle(%Sort{} = sort, field, opts) do
    default_dir = Keyword.get(opts, :default_direction, :asc)
    nulls = Keyword.get(opts, :nulls)

    new_entries =
      case direction_for(sort, field) do
        nil -> [%Entry{field: field, direction: default_dir, nulls: nulls}]
        ^default_dir -> [%Entry{field: field, direction: opposite(default_dir), nulls: nulls}]
        _ -> []
      end

    %Sort{entries: new_entries}
  end

  @doc "Sets a single explicit sort entry, replacing any current sort."
  @spec put(t(), atom(), Entry.direction(), keyword()) :: t()
  def put(%Sort{} = _sort, field, direction, opts \\ []) when direction in [:asc, :desc] do
    %Sort{
      entries: [
        %Entry{field: field, direction: direction, nulls: Keyword.get(opts, :nulls)}
      ]
    }
  end

  @doc "Clears all sort entries."
  @spec clear(t()) :: t()
  def clear(%Sort{}), do: %Sort{entries: []}

  @doc "Removes the entry for `field` (no-op if absent)."
  @spec clear(t(), atom()) :: t()
  def clear(%Sort{entries: entries}, field) do
    %Sort{entries: Enum.reject(entries, &(&1.field == field))}
  end

  @doc """
  Serializes to a PostgREST-compatible param map. Returns `%{}` (no `order` key)
  when the sort is empty, keeping default-state URLs clean.
  """
  @spec to_params(t()) :: map()
  def to_params(%Sort{entries: []}), do: %{}

  def to_params(%Sort{entries: entries}) do
    %{"order" => Enum.map_join(entries, ",", &entry_to_token/1)}
  end

  @doc false
  @spec entry_to_token(Entry.t()) :: String.t()
  def entry_to_token(%Entry{field: field, direction: direction, nulls: nulls}) do
    "#{field}.#{direction}" <> nulls_suffix(nulls)
  end

  defp nulls_suffix(:first), do: ".nullsfirst"
  defp nulls_suffix(:last), do: ".nullslast"
  defp nulls_suffix(_), do: ""

  @doc false
  @spec from_token(String.t(), %{optional(String.t()) => LiveFilter.SortField.t()}) ::
          Entry.t() | nil
  def from_token(token, by_field) do
    case String.split(token, ".", parts: 3) do
      [field_str | rest] ->
        with %LiveFilter.SortField{} = sf <- Map.get(by_field, field_str),
             {:ok, direction} <- parse_direction(rest),
             {:ok, nulls} <- parse_nulls(rest) do
          %Entry{
            field: sf.field,
            direction: direction,
            query_field: sf.query_field || sf.field,
            nulls: nulls
          }
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # "field" (bare) -> asc ; "field.asc"/".desc" -> that ; anything else -> invalid
  defp parse_direction([]), do: {:ok, :asc}
  defp parse_direction(["asc" | _]), do: {:ok, :asc}
  defp parse_direction(["desc" | _]), do: {:ok, :desc}
  defp parse_direction(_), do: :error

  defp parse_nulls([_dir]), do: {:ok, nil}
  defp parse_nulls([]), do: {:ok, nil}
  defp parse_nulls([_dir, "nullsfirst"]), do: {:ok, :first}
  defp parse_nulls([_dir, "nullslast"]), do: {:ok, :last}
  defp parse_nulls(_), do: :error

  defp opposite(:asc), do: :desc
  defp opposite(:desc), do: :asc
end
