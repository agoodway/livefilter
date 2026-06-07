# test/live_filter/sort_params_test.exs
defmodule LiveFilter.SortParamsTest do
  use ExUnit.Case, async: true
  alias LiveFilter.Sort
  alias LiveFilter.Sort.Entry

  defp fields do
    [
      LiveFilter.sort_field(:clicks, query_field: :total_clicks, default_direction: :desc),
      LiveFilter.sort_field(:created, query_field: :inserted_at),
      LiveFilter.sort_field(:name)
    ]
  end

  describe "sort_from_params/3" do
    test "parses a single order param and resolves query_field" do
      {sort, remaining} = LiveFilter.sort_from_params(%{"order" => "clicks.desc"}, fields())

      assert sort == %Sort{
               entries: [
                 %Entry{field: :clicks, direction: :desc, query_field: :total_clicks, nulls: nil}
               ]
             }

      assert remaining == %{}
    end

    test "bare field defaults to ascending" do
      {sort, _} = LiveFilter.sort_from_params(%{"order" => "name"}, fields())
      assert Sort.direction_for(sort, :name) == :asc
    end

    test "parses nulls token" do
      {sort, _} = LiveFilter.sort_from_params(%{"order" => "clicks.asc.nullslast"}, fields())
      assert [%Entry{field: :clicks, direction: :asc, nulls: :last}] = sort.entries
    end

    test "parses multiple comma-separated entries preserving order" do
      {sort, _} = LiveFilter.sort_from_params(%{"order" => "clicks.desc,name.asc"}, fields())
      assert Enum.map(sort.entries, & &1.field) == [:clicks, :name]
    end

    test "drops unknown / non-allowed fields (dynamic-list + injection safety)" do
      {sort, _} = LiveFilter.sort_from_params(%{"order" => "secret.desc,clicks.asc"}, fields())
      assert Enum.map(sort.entries, & &1.field) == [:clicks]
    end

    test "drops entries with an invalid direction or nulls token" do
      {sort, _} =
        LiveFilter.sort_from_params(%{"order" => "clicks.sideways,name.asc.bogus"}, fields())

      assert sort.entries == []
    end

    test "returns remaining params untouched" do
      {_, remaining} =
        LiveFilter.sort_from_params(
          %{"order" => "clicks.desc", "status" => "eq.active"},
          fields()
        )

      assert remaining == %{"status" => "eq.active"}
    end

    test "uses :default when no order param is present" do
      default = %Sort{entries: [%Entry{field: :clicks, direction: :desc}]}
      {sort, _} = LiveFilter.sort_from_params(%{}, fields(), default: default)
      assert sort == default
    end

    test "falls back to :default (or empty) when all entries are invalid" do
      {sort, _} = LiveFilter.sort_from_params(%{"order" => "secret.desc"}, fields())
      assert sort == %Sort{entries: []}
    end

    test "respects a provided :default when every order entry is invalid (stale URL)" do
      default = %Sort{entries: [%Entry{field: :clicks, direction: :desc}]}

      {sort, _} =
        LiveFilter.sort_from_params(%{"order" => "secret.desc"}, fields(), default: default)

      assert sort == default
    end

    test "deduplicates repeated fields, keeping the first occurrence" do
      {sort, _} = LiveFilter.sort_from_params(%{"order" => "clicks.desc,clicks.asc"}, fields())

      assert sort.entries == [
               %Entry{field: :clicks, direction: :desc, query_field: :total_clicks, nulls: nil}
             ]
    end
  end

  describe "round-trip" do
    test "to_params then sort_from_params is stable" do
      sort = %Sort{
        entries: [%Entry{field: :clicks, direction: :desc, query_field: :total_clicks}]
      }

      {parsed, _} = LiveFilter.sort_from_params(Sort.to_params(sort), fields())
      assert parsed == sort
    end

    test "round-trips nulls placement" do
      sort = %Sort{
        entries: [
          %Entry{field: :clicks, direction: :desc, query_field: :total_clicks, nulls: :last}
        ]
      }

      {parsed, _} = LiveFilter.sort_from_params(Sort.to_params(sort), fields())
      assert parsed == sort
    end
  end

  describe "toggle/3 with a SortField list" do
    test "first click uses the field's declared default_direction" do
      sort = Sort.toggle(%Sort{}, :clicks, fields())
      assert Sort.direction_for(sort, :clicks) == :desc
    end

    test "a field not in the SortField list is a no-op" do
      start = %Sort{entries: [%Entry{field: :clicks, direction: :desc}]}
      assert Sort.toggle(start, :not_sortable, fields()) == start
    end
  end
end
