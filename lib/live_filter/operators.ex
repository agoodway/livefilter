defmodule LiveFilter.Operators do
  @moduledoc """
  Human-readable labels and per-type operator option lists for UI display.
  """

  @labels %{
    eq: "is",
    neq: "is not",
    gt: "is greater than",
    gte: "is at least",
    lt: "is less than",
    lte: "is at most",
    like: "like",
    ilike: "contains",
    in: "is any of",
    not_in: "is none of",
    is: "is",
    is_null: "is null",
    cs: "contains all",
    cd: "contained by",
    ov: "contains any",
    fts: "search",
    plfts: "search",
    phfts: "phrase search",
    gte_lte: "between"
  }

  @doc """
  Returns a human-readable label for the given operator.
  """
  @spec label(atom()) :: String.t()
  def label(operator) when is_atom(operator) do
    Map.get(@labels, operator, Atom.to_string(operator))
  end

  @doc """
  Returns operator options as `[{atom, String.t()}]` tuples for the given filter type.
  """
  @spec options_for_type(atom()) :: [{atom(), String.t()}]
  def options_for_type(:text) do
    [{:ilike, "contains"}, {:eq, "equals"}, {:neq, "not equals"}, {:like, "like"}]
  end

  def options_for_type(:number) do
    [
      {:eq, "is"},
      {:neq, "is not"},
      {:lt, "is less than"},
      {:lte, "is at most"},
      {:gt, "is greater than"},
      {:gte, "is at least"}
    ]
  end

  def options_for_type(:select) do
    [{:eq, "is"}, {:neq, "is not"}]
  end

  def options_for_type(:multi_select) do
    [{:ov, "contains any"}, {:cs, "contains all"}]
  end

  def options_for_type(:date) do
    [{:eq, "is"}, {:gt, "after"}, {:gte, "on or after"}, {:lt, "before"}, {:lte, "on or before"}]
  end

  def options_for_type(:date_range) do
    [{:gte_lte, "between"}]
  end

  def options_for_type(:datetime_range) do
    [{:gte_lte, "between"}]
  end

  def options_for_type(:datetime) do
    [{:eq, "is"}, {:gt, "after"}, {:gte, "on or after"}, {:lt, "before"}, {:lte, "on or before"}]
  end

  def options_for_type(:boolean) do
    [{:is, "is"}]
  end

  def options_for_type(:radio_group) do
    [{:eq, "is"}]
  end

  @doc """
  Returns whether an operator uses single or multi-value selection.

  Multi-value operators (`:in`, `:not_in`, `:ov`, `:cs`, `:cd`) allow selecting
  multiple values, while single-value operators use a single selection.
  """
  @spec value_mode(atom()) :: :single | :multi
  def value_mode(op) when op in [:in, :not_in, :ov, :cs, :cd], do: :multi
  def value_mode(_op), do: :single
end
