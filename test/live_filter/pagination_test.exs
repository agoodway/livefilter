defmodule LiveFilter.PaginationTest do
  use ExUnit.Case

  alias LiveFilter.Pagination

  describe "new/1" do
    test "creates pagination with defaults" do
      pagination = Pagination.new()
      assert pagination.limit == 25
      assert pagination.offset == 0
      assert pagination.total_count == nil
      assert pagination.limit_options == [10, 25, 50, 100]
      assert pagination.max_limit == 100
    end

    test "accepts custom values" do
      pagination = Pagination.new(limit: 50, offset: 100, total_count: 500)
      assert pagination.limit == 50
      assert pagination.offset == 100
      assert pagination.total_count == 500
    end

    test "accepts custom limit_options and max_limit" do
      pagination = Pagination.new(limit_options: [5, 10, 20], max_limit: 50)
      assert pagination.limit_options == [5, 10, 20]
      assert pagination.max_limit == 50
    end
  end

  describe "page/1" do
    test "returns 1-indexed page number" do
      assert Pagination.page(%Pagination{limit: 25, offset: 0}) == 1
      assert Pagination.page(%Pagination{limit: 25, offset: 25}) == 2
      assert Pagination.page(%Pagination{limit: 25, offset: 50}) == 3
      assert Pagination.page(%Pagination{limit: 10, offset: 30}) == 4
    end
  end

  describe "total_pages/1" do
    test "returns nil when total_count is nil" do
      assert Pagination.total_pages(%Pagination{total_count: nil}) == nil
    end

    test "calculates total pages" do
      assert Pagination.total_pages(%Pagination{limit: 25, total_count: 100}) == 4
      assert Pagination.total_pages(%Pagination{limit: 25, total_count: 101}) == 5
      assert Pagination.total_pages(%Pagination{limit: 10, total_count: 100}) == 10
      assert Pagination.total_pages(%Pagination{limit: 25, total_count: 1}) == 1
    end
  end

  describe "has_prev?/1" do
    test "returns false when on first page" do
      refute Pagination.has_prev?(%Pagination{offset: 0})
    end

    test "returns true when not on first page" do
      assert Pagination.has_prev?(%Pagination{offset: 25})
      assert Pagination.has_prev?(%Pagination{offset: 1})
    end
  end

  describe "has_next?/1" do
    test "returns false when total_count is nil" do
      refute Pagination.has_next?(%Pagination{total_count: nil})
    end

    test "returns false on last page" do
      refute Pagination.has_next?(%Pagination{limit: 25, offset: 75, total_count: 100})
      refute Pagination.has_next?(%Pagination{limit: 25, offset: 99, total_count: 100})
    end

    test "returns true when more pages available" do
      assert Pagination.has_next?(%Pagination{limit: 25, offset: 0, total_count: 100})
      assert Pagination.has_next?(%Pagination{limit: 25, offset: 50, total_count: 100})
    end
  end

  describe "start_item/1" do
    test "returns 1-indexed start item" do
      assert Pagination.start_item(%Pagination{offset: 0}) == 1
      assert Pagination.start_item(%Pagination{offset: 25}) == 26
      assert Pagination.start_item(%Pagination{offset: 50}) == 51
    end
  end

  describe "end_item/1" do
    test "returns end item without total_count" do
      assert Pagination.end_item(%Pagination{limit: 25, offset: 0, total_count: nil}) == 25
      assert Pagination.end_item(%Pagination{limit: 25, offset: 25, total_count: nil}) == 50
    end

    test "caps at total_count when known" do
      assert Pagination.end_item(%Pagination{limit: 25, offset: 0, total_count: 100}) == 25
      assert Pagination.end_item(%Pagination{limit: 25, offset: 75, total_count: 100}) == 100
      assert Pagination.end_item(%Pagination{limit: 25, offset: 90, total_count: 95}) == 95
    end
  end

  describe "with_total/2" do
    test "sets total_count" do
      pagination = %Pagination{limit: 25, offset: 0}
      updated = Pagination.with_total(pagination, 127)
      assert updated.total_count == 127
      assert updated.limit == 25
      assert updated.offset == 0
    end
  end

  describe "prev_page/1" do
    test "decrements offset by limit" do
      pagination = %Pagination{limit: 25, offset: 50}
      prev = Pagination.prev_page(pagination)
      assert prev.offset == 25
    end

    test "clamps to 0 on first page" do
      pagination = %Pagination{limit: 25, offset: 10}
      prev = Pagination.prev_page(pagination)
      assert prev.offset == 0
    end

    test "stays at 0 when already on first page" do
      pagination = %Pagination{limit: 25, offset: 0}
      prev = Pagination.prev_page(pagination)
      assert prev.offset == 0
    end
  end

  describe "next_page/1" do
    test "increments offset by limit" do
      pagination = %Pagination{limit: 25, offset: 0}
      next = Pagination.next_page(pagination)
      assert next.offset == 25
    end
  end

  describe "go_to_page/2" do
    test "sets offset for given page" do
      pagination = %Pagination{limit: 25}
      assert Pagination.go_to_page(pagination, 1).offset == 0
      assert Pagination.go_to_page(pagination, 2).offset == 25
      assert Pagination.go_to_page(pagination, 5).offset == 100
    end

    test "clamps to max valid offset when total_count known" do
      pagination = %Pagination{limit: 25, total_count: 100}
      assert Pagination.go_to_page(pagination, 10).offset == 99
    end

    test "allows any page when total_count unknown" do
      pagination = %Pagination{limit: 25, total_count: nil}
      assert Pagination.go_to_page(pagination, 100).offset == 2475
    end
  end

  describe "change_limit/2" do
    test "sets new limit and resets offset" do
      pagination = %Pagination{limit: 25, offset: 50}
      updated = Pagination.change_limit(pagination, 50)
      assert updated.limit == 50
      assert updated.offset == 0
    end

    test "clamps limit to max_limit" do
      pagination = %Pagination{max_limit: 100}
      updated = Pagination.change_limit(pagination, 200)
      assert updated.limit == 100
    end
  end

  describe "reset/1" do
    test "resets offset to 0" do
      pagination = %Pagination{limit: 25, offset: 100}
      reset = Pagination.reset(pagination)
      assert reset.offset == 0
      assert reset.limit == 25
    end
  end

  describe "edge cases" do
    test "total_pages with total_count = 0 returns 0" do
      assert Pagination.total_pages(%Pagination{limit: 25, total_count: 0}) == 0
    end

    test "has_next? with total_count = 0 returns false" do
      refute Pagination.has_next?(%Pagination{limit: 25, offset: 0, total_count: 0})
    end

    test "end_item with total_count = 0 returns 0" do
      assert Pagination.end_item(%Pagination{limit: 25, offset: 0, total_count: 0}) == 0
    end

    test "go_to_page clamps to @max_offset when total_count is nil" do
      pagination = %Pagination{limit: 25, total_count: nil}
      # Page 10000 would be offset 249,975, but max_offset is 100,000
      result = Pagination.go_to_page(pagination, 10_000)
      assert result.offset == 100_000
    end

    test "go_to_page with total_count = 0 clamps to offset 0" do
      pagination = %Pagination{limit: 25, total_count: 0}
      result = Pagination.go_to_page(pagination, 5)
      assert result.offset == 0
    end

    test "go_to_page with total_count = 1 clamps to offset 0" do
      pagination = %Pagination{limit: 25, total_count: 1}
      result = Pagination.go_to_page(pagination, 5)
      assert result.offset == 0
    end

    test "start_item returns 1 even with total_count = 0" do
      assert Pagination.start_item(%Pagination{offset: 0, total_count: 0}) == 1
    end
  end
end
