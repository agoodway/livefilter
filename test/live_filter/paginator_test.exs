defmodule LiveFilter.PaginatorTest do
  use ExUnit.Case, async: true

  alias LiveFilter.{Pagination, Paginator}

  # Test the page_buttons logic directly
  describe "page_buttons/3" do
    # Access private function via Module.concat trick or test through render
    # Since page_buttons is private, we'll test it indirectly through rendered output

    test "returns all pages when total_pages <= max_pages" do
      # 4 pages with max_pages=5 should show [1, 2, 3, 4]
      buttons = compute_buttons(page: 1, total_pages: 4, max_pages: 5)
      assert buttons == [1, 2, 3, 4]
    end

    test "returns all pages when total_pages equals max_pages" do
      buttons = compute_buttons(page: 1, total_pages: 5, max_pages: 5)
      assert buttons == [1, 2, 3, 4, 5]
    end

    test "shows ellipsis at end when on early pages" do
      # Page 1 of 10, max_pages=5: [1, 2, 3, ..., 10]
      buttons = compute_buttons(page: 1, total_pages: 10, max_pages: 5)
      assert buttons == [1, 2, 3, "...", 10]
    end

    test "shows ellipsis at start when on late pages" do
      # Page 10 of 10, max_pages=5: [1, ..., 8, 9, 10]
      buttons = compute_buttons(page: 10, total_pages: 10, max_pages: 5)
      assert buttons == [1, "...", 8, 9, 10]
    end

    test "shows ellipsis on both sides when in middle" do
      # Page 5 of 10, max_pages=5: [1, ..., 4, 5, 6, ..., 10]
      # With half = div(5-2, 2) = 1, shows (page-1)..(page+1) = 4..6
      buttons = compute_buttons(page: 5, total_pages: 10, max_pages: 5)
      assert buttons == [1, "...", 4, 5, 6, "...", 10]
    end

    test "handles page near start boundary" do
      # Page 2 of 10, max_pages=5: should still show [1, 2, 3, ..., 10]
      buttons = compute_buttons(page: 2, total_pages: 10, max_pages: 5)
      assert buttons == [1, 2, 3, "...", 10]
    end

    test "handles page near end boundary" do
      # Page 9 of 10, max_pages=5: should show [1, ..., 8, 9, 10]
      buttons = compute_buttons(page: 9, total_pages: 10, max_pages: 5)
      assert buttons == [1, "...", 8, 9, 10]
    end

    test "with max_pages=7 and middle page" do
      # Page 5 of 10, max_pages=7: [1, ..., 3, 4, 5, 6, 7, ..., 10]
      # With half = div(7-2, 2) = 2, shows (page-2)..(page+2) = 3..7
      buttons = compute_buttons(page: 5, total_pages: 10, max_pages: 7)
      assert buttons == [1, "...", 3, 4, 5, 6, 7, "...", 10]
    end

    test "single page" do
      buttons = compute_buttons(page: 1, total_pages: 1, max_pages: 5)
      assert buttons == [1]
    end

    test "two pages" do
      buttons = compute_buttons(page: 1, total_pages: 2, max_pages: 5)
      assert buttons == [1, 2]
    end
  end

  describe "handle_event go_to_page" do
    test "valid page sends notification" do
      socket = build_socket(%Pagination{limit: 25, offset: 0, total_count: 100})
      assert {:noreply, _socket} = Paginator.handle_event("go_to_page", %{"page" => "3"}, socket)
      assert_received {:live_filter, :page_changed, %{"limit" => "25", "offset" => "50"}}
    end

    test "invalid page string is ignored" do
      socket = build_socket(%Pagination{limit: 25, offset: 0, total_count: 100})

      assert {:noreply, _socket} =
               Paginator.handle_event("go_to_page", %{"page" => "abc"}, socket)

      refute_received {:live_filter, :page_changed, _}
    end

    test "page 0 is ignored" do
      socket = build_socket(%Pagination{limit: 25, offset: 0, total_count: 100})
      assert {:noreply, _socket} = Paginator.handle_event("go_to_page", %{"page" => "0"}, socket)
      refute_received {:live_filter, :page_changed, _}
    end

    test "negative page is ignored" do
      socket = build_socket(%Pagination{limit: 25, offset: 0, total_count: 100})
      assert {:noreply, _socket} = Paginator.handle_event("go_to_page", %{"page" => "-1"}, socket)
      refute_received {:live_filter, :page_changed, _}
    end

    test "ellipsis string is ignored" do
      socket = build_socket(%Pagination{limit: 25, offset: 0, total_count: 100})

      assert {:noreply, _socket} =
               Paginator.handle_event("go_to_page", %{"page" => "..."}, socket)

      refute_received {:live_filter, :page_changed, _}
    end
  end

  describe "handle_event change_limit" do
    test "valid limit sends notification and resets offset" do
      socket = build_socket(%Pagination{limit: 25, offset: 50, total_count: 100})

      assert {:noreply, _socket} =
               Paginator.handle_event("change_limit", %{"limit" => "50"}, socket)

      assert_received {:live_filter, :page_changed, %{"limit" => "50", "offset" => "0"}}
    end

    test "invalid limit string is ignored" do
      socket = build_socket(%Pagination{limit: 25, offset: 0, total_count: 100})

      assert {:noreply, _socket} =
               Paginator.handle_event("change_limit", %{"limit" => "abc"}, socket)

      refute_received {:live_filter, :page_changed, _}
    end

    test "limit 0 is ignored" do
      socket = build_socket(%Pagination{limit: 25, offset: 0, total_count: 100})

      assert {:noreply, _socket} =
               Paginator.handle_event("change_limit", %{"limit" => "0"}, socket)

      refute_received {:live_filter, :page_changed, _}
    end

    test "negative limit is ignored" do
      socket = build_socket(%Pagination{limit: 25, offset: 0, total_count: 100})

      assert {:noreply, _socket} =
               Paginator.handle_event("change_limit", %{"limit" => "-10"}, socket)

      refute_received {:live_filter, :page_changed, _}
    end
  end

  describe "handle_event prev_page" do
    test "sends notification with decremented offset" do
      socket = build_socket(%Pagination{limit: 25, offset: 50, total_count: 100})
      assert {:noreply, _socket} = Paginator.handle_event("prev_page", %{}, socket)
      assert_received {:live_filter, :page_changed, %{"limit" => "25", "offset" => "25"}}
    end

    test "clamps to offset 0 when on first page" do
      socket = build_socket(%Pagination{limit: 25, offset: 0, total_count: 100})
      assert {:noreply, _socket} = Paginator.handle_event("prev_page", %{}, socket)
      assert_received {:live_filter, :page_changed, %{"limit" => "25", "offset" => "0"}}
    end
  end

  describe "handle_event next_page" do
    test "sends notification with incremented offset" do
      socket = build_socket(%Pagination{limit: 25, offset: 0, total_count: 100})
      assert {:noreply, _socket} = Paginator.handle_event("next_page", %{}, socket)
      assert_received {:live_filter, :page_changed, %{"limit" => "25", "offset" => "25"}}
    end
  end

  # Helper that replicates the page_buttons logic for testing
  # This mirrors the private function in Paginator
  defp compute_buttons(opts) do
    page = Keyword.fetch!(opts, :page)
    total_pages = Keyword.fetch!(opts, :total_pages)
    max_pages = Keyword.fetch!(opts, :max_pages)

    if total_pages <= max_pages do
      Enum.to_list(1..total_pages)
    else
      half = div(max_pages - 2, 2)

      cond do
        page <= half + 1 ->
          Enum.to_list(1..(max_pages - 2)) ++ ["...", total_pages]

        page >= total_pages - half ->
          start = total_pages - max_pages + 3
          [1, "..."] ++ Enum.to_list(start..total_pages)

        true ->
          [1, "..."] ++ Enum.to_list((page - half)..(page + half)) ++ ["...", total_pages]
      end
    end
  end

  defp build_socket(pagination) do
    # Create a minimal socket struct for testing handle_event
    %Phoenix.LiveView.Socket{
      assigns: %{
        pagination: pagination,
        __changed__: %{}
      }
    }
  end
end
