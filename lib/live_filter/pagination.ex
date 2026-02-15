defmodule LiveFilter.Pagination do
  @moduledoc """
  Pagination state with PostgREST-compatible limit/offset.

  Provides computed properties for page number, total pages, and navigation state.
  Uses strict PostgREST URL parameters (`limit`/`offset`) for compatibility.

  ## Example

      # Parse from URL params
      {pagination, remaining} = LiveFilter.pagination_from_params(params, default_limit: 25)

      # Access computed properties
      LiveFilter.Pagination.page(pagination)         # => 3
      LiveFilter.Pagination.total_pages(pagination)  # => 10
      LiveFilter.Pagination.has_next?(pagination)    # => true

      # Serialize back to URL params
      LiveFilter.Params.Serializer.pagination_to_params(pagination)
      # => %{"limit" => "25", "offset" => "50"}
  """

  @max_offset 100_000

  @type t :: %__MODULE__{
          limit: pos_integer(),
          offset: non_neg_integer(),
          total_count: non_neg_integer() | nil,
          limit_options: [pos_integer()],
          max_limit: pos_integer()
        }

  defstruct limit: 25,
            offset: 0,
            total_count: nil,
            limit_options: [10, 25, 50, 100],
            max_limit: 100

  @doc """
  Creates a new pagination struct with the given options.

  ## Options

    * `:limit` - Number of items per page (default: 25)
    * `:offset` - Number of items to skip (default: 0)
    * `:total_count` - Total number of items (default: nil)
    * `:limit_options` - Available per-page options for UI dropdown (default: [10, 25, 50, 100])
    * `:max_limit` - Maximum allowed limit value (default: 100)

  ## Example

      iex> LiveFilter.Pagination.new(limit: 50, offset: 100)
      %LiveFilter.Pagination{limit: 50, offset: 100, ...}
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end

  @doc """
  Returns the current page number (1-indexed).

  ## Example

      iex> pagination = %LiveFilter.Pagination{limit: 25, offset: 50}
      iex> LiveFilter.Pagination.page(pagination)
      3
  """
  @spec page(t()) :: pos_integer()
  def page(%__MODULE__{offset: offset, limit: limit}) do
    div(offset, limit) + 1
  end

  @doc """
  Returns the total number of pages, or nil if total_count is unknown.

  ## Example

      iex> pagination = %LiveFilter.Pagination{limit: 25, total_count: 100}
      iex> LiveFilter.Pagination.total_pages(pagination)
      4
  """
  @spec total_pages(t()) :: pos_integer() | nil
  def total_pages(%__MODULE__{total_count: nil}), do: nil

  def total_pages(%__MODULE__{total_count: total, limit: limit}) do
    ceil(total / limit)
  end

  @doc """
  Returns true if there is a previous page.

  ## Example

      iex> pagination = %LiveFilter.Pagination{offset: 25}
      iex> LiveFilter.Pagination.has_prev?(pagination)
      true
  """
  @spec has_prev?(t()) :: boolean()
  def has_prev?(%__MODULE__{offset: offset}), do: offset > 0

  @doc """
  Returns true if there is a next page.

  Returns false if total_count is nil (unknown).

  ## Example

      iex> pagination = %LiveFilter.Pagination{limit: 25, offset: 0, total_count: 100}
      iex> LiveFilter.Pagination.has_next?(pagination)
      true
  """
  @spec has_next?(t()) :: boolean()
  def has_next?(%__MODULE__{total_count: nil}), do: false

  def has_next?(%__MODULE__{offset: offset, limit: limit, total_count: total}) do
    offset + limit < total
  end

  @doc """
  Returns the 1-indexed start item number for display.

  ## Example

      iex> pagination = %LiveFilter.Pagination{offset: 50}
      iex> LiveFilter.Pagination.start_item(pagination)
      51
  """
  @spec start_item(t()) :: pos_integer()
  def start_item(%__MODULE__{offset: offset}), do: offset + 1

  @doc """
  Returns the end item number for display.

  Capped at total_count if known.

  ## Example

      iex> pagination = %LiveFilter.Pagination{limit: 25, offset: 50, total_count: 60}
      iex> LiveFilter.Pagination.end_item(pagination)
      60
  """
  @spec end_item(t()) :: pos_integer()
  def end_item(%__MODULE__{offset: offset, limit: limit, total_count: nil}) do
    offset + limit
  end

  def end_item(%__MODULE__{offset: offset, limit: limit, total_count: total}) do
    min(offset + limit, total)
  end

  @doc """
  Updates the pagination with a new total count and computes navigation state.

  ## Example

      iex> pagination = %LiveFilter.Pagination{limit: 25, offset: 50}
      iex> LiveFilter.Pagination.with_total(pagination, 127)
      %LiveFilter.Pagination{limit: 25, offset: 50, total_count: 127, ...}
  """
  @spec with_total(t(), non_neg_integer()) :: t()
  def with_total(%__MODULE__{} = pagination, total_count) do
    %{pagination | total_count: total_count}
  end

  @doc """
  Returns pagination for the previous page, or the same pagination if already on page 1.

  ## Example

      iex> pagination = %LiveFilter.Pagination{limit: 25, offset: 50}
      iex> prev = LiveFilter.Pagination.prev_page(pagination)
      iex> prev.offset
      25
  """
  @spec prev_page(t()) :: t()
  def prev_page(%__MODULE__{offset: offset, limit: limit} = pagination) do
    %{pagination | offset: max(0, offset - limit)}
  end

  @doc """
  Returns pagination for the next page.

  Does not check if a next page exists — caller should check `has_next?/1`.

  ## Example

      iex> pagination = %LiveFilter.Pagination{limit: 25, offset: 50}
      iex> next = LiveFilter.Pagination.next_page(pagination)
      iex> next.offset
      75
  """
  @spec next_page(t()) :: t()
  def next_page(%__MODULE__{offset: offset, limit: limit} = pagination) do
    %{pagination | offset: offset + limit}
  end

  @doc """
  Returns pagination for a specific page number (1-indexed).

  Clamps to valid page range if total_count is known.

  ## Example

      iex> pagination = %LiveFilter.Pagination{limit: 25, total_count: 100}
      iex> page5 = LiveFilter.Pagination.go_to_page(pagination, 5)
      iex> page5.offset
      100  # Clamped to max valid offset
  """
  @spec go_to_page(t(), pos_integer()) :: t()
  def go_to_page(%__MODULE__{limit: limit} = pagination, page)
      when is_integer(page) and page >= 1 do
    new_offset = (page - 1) * limit
    new_offset = clamp_offset(new_offset, pagination.total_count)
    %{pagination | offset: new_offset}
  end

  defp clamp_offset(offset, nil), do: min(offset, @max_offset)
  defp clamp_offset(offset, total), do: min(offset, min(@max_offset, max(0, total - 1)))

  @doc """
  Returns pagination with a new limit (items per page).

  Resets offset to 0 to start at page 1.

  ## Example

      iex> pagination = %LiveFilter.Pagination{limit: 25, offset: 50}
      iex> new_pagination = LiveFilter.Pagination.change_limit(pagination, 50)
      iex> {new_pagination.limit, new_pagination.offset}
      {50, 0}
  """
  @spec change_limit(t(), pos_integer()) :: t()
  def change_limit(%__MODULE__{max_limit: max_limit} = pagination, new_limit)
      when is_integer(new_limit) and new_limit > 0 do
    clamped_limit = min(new_limit, max_limit)
    %{pagination | limit: clamped_limit, offset: 0}
  end

  @doc """
  Resets pagination to the first page (offset: 0).

  ## Example

      iex> pagination = %LiveFilter.Pagination{limit: 25, offset: 100}
      iex> reset = LiveFilter.Pagination.reset(pagination)
      iex> reset.offset
      0
  """
  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = pagination) do
    %{pagination | offset: 0}
  end
end
