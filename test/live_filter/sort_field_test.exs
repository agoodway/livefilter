defmodule LiveFilter.SortFieldTest do
  use ExUnit.Case, async: true
  alias LiveFilter.SortField

  test "sort_field/2 builds a struct with sensible defaults" do
    sf = LiveFilter.sort_field(:clicks)

    assert %SortField{
             field: :clicks,
             label: "Clicks",
             query_field: nil,
             default_direction: :asc,
             nulls: nil
           } = sf
  end

  test "sort_field/2 honors options" do
    sf =
      LiveFilter.sort_field(:clicks,
        label: "Total clicks",
        query_field: :total_clicks,
        default_direction: :desc,
        nulls: :last
      )

    assert %SortField{
             field: :clicks,
             label: "Total clicks",
             query_field: :total_clicks,
             default_direction: :desc,
             nulls: :last
           } = sf
  end

  test "default label capitalizes the field name" do
    assert LiveFilter.sort_field(:created_at).label == "Created_at"
  end

  test "rejects an invalid default_direction" do
    assert_raise ArgumentError, fn -> LiveFilter.sort_field(:clicks, default_direction: :up) end
  end
end
