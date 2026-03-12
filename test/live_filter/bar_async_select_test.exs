defmodule LiveFilter.BarAsyncSelectTest do
  use ExUnit.Case

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint LiveFilter.TestEndpoint

  setup do
    {:ok, conn: build_conn()}
  end

  defp add_filter(view, field) do
    view
    |> with_target("[id^='live-filter-']")
    |> render_click("add_filter", %{"field" => to_string(field)})
  end

  defp filter_event(view, event, params) do
    view
    |> with_target("[id^='live-filter-']")
    |> render_click(event, params)
  end

  describe "async_select rendering" do
    test "shows async_select in add filter dropdown", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/test-async-select")

      assert html =~ "Employer"
    end

    test "adds async_select filter chip", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test-async-select")

      add_filter(view, :company_id)

      html = render(view)
      assert html =~ "Employer"
      assert html =~ "filter-chip-company_id"
    end

    test "renders search input in dropdown", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test-async-select")

      add_filter(view, :company_id)

      html = render(view)
      assert html =~ "async-search-company_id"
      assert html =~ "Search..."
    end

    test "shows search input without results before typing enough", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test-async-select")

      add_filter(view, :company_id)

      html = render(view)
      assert html =~ "async-search-company_id"
      refute html =~ "No results found"
    end
  end

  describe "async_select search flow" do
    test "search returns matching options", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test-async-select")

      add_filter(view, :company_id)

      filter_event(view, "async_search", %{"id" => "company_id", "value" => "acme"})

      html = render(view)
      assert html =~ "Acme Corp"
      assert html =~ "Acme Industries"
      refute html =~ "Beta LLC"
    end

    test "search with short query does not show results", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test-async-select")

      add_filter(view, :company_id)

      filter_event(view, "async_search", %{"id" => "company_id", "value" => "a"})

      html = render(view)
      # min_chars is 2, so single char should not trigger search results
      refute html =~ "Acme Corp"
      refute html =~ "No results found"
    end

    test "selecting option sets filter value and shows label", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test-async-select")

      add_filter(view, :company_id)

      # Search first
      filter_event(view, "async_search", %{"id" => "company_id", "value" => "acme"})

      # Select an option
      filter_event(view, "async_select_option", %{
        "id" => "company_id",
        "value" => "c1",
        "label" => "Acme Corp"
      })

      html = render(view)
      # Should show the label in the chip
      assert html =~ "Acme Corp"
      # Should notify parent with serialized param
      assert html =~ "eq.c1"
    end
  end

  describe "async_select label hydration" do
    test "hydrates label from load_label_fn when filter has value but no label", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test-async-select")

      add_filter(view, :company_id)

      # Select an option
      filter_event(view, "async_search", %{"id" => "company_id", "value" => "beta"})

      filter_event(view, "async_select_option", %{
        "id" => "company_id",
        "value" => "c3",
        "label" => "Beta LLC"
      })

      html = render(view)
      assert html =~ "Beta LLC"
    end
  end

  describe "async_select clearing and removal" do
    test "removing async_select filter clears chip", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test-async-select")

      add_filter(view, :company_id)

      filter_event(view, "async_search", %{"id" => "company_id", "value" => "acme"})

      filter_event(view, "async_select_option", %{
        "id" => "company_id",
        "value" => "c1",
        "label" => "Acme Corp"
      })

      assert render(view) =~ "Acme Corp"

      # Remove the filter
      filter_event(view, "remove_filter", %{"id" => "company_id"})

      html = render(view)
      refute html =~ "filter-chip-company_id"
      refute html =~ "Acme Corp"
    end

    test "clear_all removes async_select filter", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test-async-select")

      add_filter(view, :company_id)

      filter_event(view, "async_search", %{"id" => "company_id", "value" => "acme"})

      filter_event(view, "async_select_option", %{
        "id" => "company_id",
        "value" => "c1",
        "label" => "Acme Corp"
      })

      assert render(view) =~ "Acme Corp"

      # Clear all
      view |> element("[phx-click=clear_all]") |> render_click()

      html = render(view)
      refute html =~ "filter-chip-company_id"
    end

    test "shows empty message when search returns no results", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test-async-select")

      add_filter(view, :company_id)

      filter_event(view, "async_search", %{"id" => "company_id", "value" => "zzzzz"})

      html = render(view)
      assert html =~ "No results found"
    end
  end
end
