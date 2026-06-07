defmodule LiveFilter.SortField do
  @moduledoc """
  A declaration of a sortable field: the allow-list item the sort dropdown
  lists and that `LiveFilter.sort_from_params/3` validates incoming `order=`
  params against. Pass a static or runtime-built list (e.g. driven by a user's
  table-column settings).
  """
  @type t :: %__MODULE__{
          field: atom(),
          label: String.t(),
          query_field: atom() | nil,
          default_direction: :asc | :desc,
          nulls: nil | :first | :last
        }
  defstruct [:field, :label, :query_field, default_direction: :asc, nulls: nil]
end
