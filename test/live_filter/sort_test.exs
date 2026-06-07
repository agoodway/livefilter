defmodule LiveFilter.SortTest do
  use ExUnit.Case, async: true
  alias LiveFilter.Sort
  alias LiveFilter.Sort.Entry

  describe "direction_for/2" do
    test "returns the direction of a sorted field, or nil" do
      sort = %Sort{entries: [%Entry{field: :clicks, direction: :desc}]}
      assert Sort.direction_for(sort, :clicks) == :desc
      assert Sort.direction_for(sort, :created) == nil
    end
  end

  describe "toggle/3 (single-sort tri-state cycle)" do
    test "unsorted -> default_direction" do
      sort = Sort.toggle(%Sort{}, :clicks, default_direction: :desc)
      assert sort == %Sort{entries: [%Entry{field: :clicks, direction: :desc, nulls: nil}]}
    end

    test "default_direction -> opposite" do
      start = %Sort{entries: [%Entry{field: :clicks, direction: :desc}]}

      assert Sort.toggle(start, :clicks, default_direction: :desc) ==
               %Sort{entries: [%Entry{field: :clicks, direction: :asc, nulls: nil}]}
    end

    test "opposite -> cleared" do
      start = %Sort{entries: [%Entry{field: :clicks, direction: :asc}]}
      assert Sort.toggle(start, :clicks, default_direction: :desc) == %Sort{entries: []}
    end

    test "default_direction defaults to :asc" do
      assert Sort.toggle(%Sort{}, :name) ==
               %Sort{entries: [%Entry{field: :name, direction: :asc, nulls: nil}]}
    end

    test "switching to a different field replaces the active sort" do
      start = %Sort{entries: [%Entry{field: :clicks, direction: :desc}]}

      assert Sort.toggle(start, :created, default_direction: :asc) ==
               %Sort{entries: [%Entry{field: :created, direction: :asc, nulls: nil}]}
    end

    test "carries nulls placement onto the new entry" do
      sort = Sort.toggle(%Sort{}, :clicks, default_direction: :desc, nulls: :last)
      assert sort == %Sort{entries: [%Entry{field: :clicks, direction: :desc, nulls: :last}]}
    end
  end

  describe "put/4 and clear/1" do
    test "put sets a single explicit entry" do
      assert Sort.put(%Sort{}, :revenue, :desc) ==
               %Sort{entries: [%Entry{field: :revenue, direction: :desc, nulls: nil}]}
    end

    test "clear removes all entries" do
      assert Sort.clear(%Sort{entries: [%Entry{field: :clicks, direction: :desc}]}) == %Sort{
               entries: []
             }
    end
  end

  describe "to_params/1" do
    test "empty sort serializes to an empty map (no order key)" do
      assert Sort.to_params(%Sort{}) == %{}
    end

    test "single entry -> order=field.dir" do
      sort = %Sort{entries: [%Entry{field: :clicks, direction: :desc}]}
      assert Sort.to_params(sort) == %{"order" => "clicks.desc"}
    end

    test "nulls placement -> nullslast/nullsfirst suffix" do
      sort = %Sort{entries: [%Entry{field: :clicks, direction: :desc, nulls: :last}]}
      assert Sort.to_params(sort) == %{"order" => "clicks.desc.nullslast"}
    end

    test "multiple entries -> comma-joined order" do
      sort = %Sort{
        entries: [
          %Entry{field: :clicks, direction: :desc},
          %Entry{field: :created, direction: :asc}
        ]
      }

      assert Sort.to_params(sort) == %{"order" => "clicks.desc,created.asc"}
    end
  end
end
