defmodule LiveFilter.Types do
  @moduledoc """
  Type definitions for LiveFilter.
  """

  @type filter_type ::
          :text
          | :number
          | :select
          | :multi_select
          | :date
          | :date_range
          | :datetime
          | :boolean
          | :radio_group

  @type operator ::
          :eq
          | :neq
          | :gt
          | :gte
          | :lt
          | :lte
          | :like
          | :ilike
          | :in
          | :is
          | :is_null
          | :cs
          | :cd
          | :ov
          | :fts
          | :plfts
          | :phfts
          | :gte_lte

  @type filter_value :: String.t() | number() | boolean() | [String.t()] | {term(), term()} | nil
end
