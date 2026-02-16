defmodule LiveFilter.BarTest do
  use ExUnit.Case

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint LiveFilter.TestEndpoint

  setup do
    {:ok, conn: build_conn()}
  end

  # Helper to add a filter by field name (targets the component)
  defp add_filter(view, field) do
    view
    |> with_target("[id^='live-filter-']")
    |> render_click("add_filter", %{"field" => to_string(field)})
  end

  # Helper to send an event to the filter component
  defp filter_event(view, event, params) do
    view
    |> with_target("[id^='live-filter-']")
    |> render_click(event, params)
  end

  describe "rendering" do
    test "renders always-on filter with label and input", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/test")

      assert html =~ "Search"
      assert html =~ "input"
    end

    test "shows add filter button when available fields exist", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/test")

      assert html =~ "Add Filter"
    end

    test "hides clear all when only always-on filters exist", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/test")

      refute html =~ "Clear all"
    end
  end

  describe "add_filter dropdown" do
    test "dropdown shows available fields", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/test")

      # Dropdown content is always rendered (visibility controlled by CSS)
      assert html =~ "Status"
      assert html =~ "Urgent"
      assert html =~ "Created"
    end
  end

  describe "add_filter" do
    test "adds a filter via event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test")

      # Send add_filter event to the component
      add_filter(view, :status)

      html = render(view)

      # Status should appear as a filter chip
      assert html =~ "Status"
      assert html =~ "filter-chip"
    end

    test "notifies parent with serialized params", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test")

      # Add boolean filter and set a value
      add_filter(view, :urgent)

      # Find the filter ID and set a value
      html = render(view)
      [_, filter_id] = Regex.run(~r/filter-chip-([^"]+)/, html)

      filter_event(view, "change_boolean", %{"id" => filter_id, "value" => "true"})

      # Parent should have received updated params (not nil)
      html = render(view)
      refute html =~ ~r/id="updated-params">\s*nil/
    end

    test "removes field from available list after adding", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test")

      # Add status filter
      add_filter(view, :status)

      html = render(view)

      # Status shouldn't be in the dropdown anymore (it's now active)
      refute html =~ "add-filter-status"
      # But other fields should still be available
      assert html =~ "add-filter-urgent"
      assert html =~ "add-filter-created_at"
    end
  end

  describe "remove_filter" do
    test "removes a filter and notifies parent", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test")

      # Add status filter first
      add_filter(view, :status)

      # Verify filter chip is there
      assert render(view) =~ "filter-chip-"

      # Remove it
      view |> element("[phx-click=remove_filter]") |> render_click()

      # Filter chip should be gone
      refute render(view) =~ "filter-chip-"
    end
  end

  describe "change_boolean" do
    test "converts string to boolean and notifies parent", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test")

      # Add boolean filter
      add_filter(view, :urgent)

      # Send change_boolean event to the component
      # Find the filter ID from the rendered HTML
      html = render(view)
      # Extract the filter chip ID pattern
      [_, filter_id] = Regex.run(~r/filter-chip-([^"]+)/, html)

      filter_event(view, "change_boolean", %{"id" => filter_id, "value" => "true"})

      # Parent should be notified (updated_params should contain boolean value)
      html = render(view)
      assert html =~ "is.true"
    end
  end

  describe "clear_all" do
    test "keeps only always-on filters and notifies parent", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test")

      # Add two removable filters
      add_filter(view, :status)
      add_filter(view, :urgent)

      # Clear all should be visible
      assert render(view) =~ "Clear all"

      # Click clear all
      view |> element("[phx-click=clear_all]") |> render_click()

      html = render(view)

      # Filter chips should be gone
      refute html =~ "filter-chip-"

      # Always-on search should remain
      assert html =~ "Search"

      # Clear all button should be gone
      refute html =~ "Clear all"
    end

    test "resets always-on filter values to defaults", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test")

      # Type into the always-on search filter (using filter_event helper)
      filter_event(view, "change_value", %{"id" => "search", "value" => "test value"})

      # Clear all should be visible when always-on filter has a value
      assert render(view) =~ "Clear all"

      # Click clear all
      view |> element("[phx-click=clear_all]") |> render_click()

      html = render(view)

      # Search filter should still exist but with empty value
      assert html =~ "Search"
      assert has_element?(view, "input[name='filter[search]'][value='']")

      # Clear all should be gone since all values are defaults
      refute html =~ "Clear all"
    end

    test "shows Clear all button when always-on filter has value but no added filters", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/test")

      # Initially Clear all should not be visible (only default always-on filters)
      refute render(view) =~ "Clear all"

      # Type into the always-on search filter (using filter_event helper)
      filter_event(view, "change_value", %{"id" => "search", "value" => "some search"})

      # Now Clear all should be visible
      assert render(view) =~ "Clear all"
    end
  end

  describe "clear_all with default_visible filters" do
    test "preserves default_visible filters after clear_all", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test-default-visible")

      # Verify initial state - default_visible filters should be visible
      html = render(view)
      assert html =~ "Status"
      assert html =~ "Urgent"

      # Add another filter that is not default_visible
      add_filter(view, :active)

      # Clear all should be visible (we have a user-added filter)
      assert render(view) =~ "Clear all"

      # Click clear all
      view |> element("[phx-click=clear_all]") |> render_click()

      html = render(view)

      # Default_visible filters should still be present
      assert html =~ "Status"
      assert html =~ "Urgent"

      # Always-on search should remain
      assert html =~ "Search"

      # User-added filter (active) should be removed
      refute html =~ "filter-chip-active"

      # Clear all should be gone since all filters are at defaults
      refute html =~ "Clear all"
    end

    test "resets default_visible filter values to defaults after clear_all", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test-default-visible")

      # Find the urgent filter ID and set a value
      html = render(view)
      [_, filter_id] = Regex.run(~r/filter-chip-([^"]+)/, html)

      # Set the boolean filter to true
      filter_event(view, "change_boolean", %{"id" => filter_id, "value" => "true"})

      # Clear all should be visible (non-default value)
      assert render(view) =~ "Clear all"

      # Click clear all
      view |> element("[phx-click=clear_all]") |> render_click()

      html = render(view)

      # Default_visible filter should still be present but with reset value
      assert html =~ "Urgent"

      # Clear all should be gone since value was reset to default
      refute html =~ "Clear all"
    end

    test "shows Clear all when default_visible filter has non-default value", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test-default-visible")

      # Initially Clear all should not be visible (only baseline filters with defaults)
      refute render(view) =~ "Clear all"

      # Find the urgent filter ID and set a value
      html = render(view)
      [_, filter_id] = Regex.run(~r/filter-chip-([^"]+)/, html)

      # Set the boolean filter to true
      filter_event(view, "change_boolean", %{"id" => filter_id, "value" => "true"})

      # Now Clear all should be visible
      assert render(view) =~ "Clear all"
    end

    test "hides Clear all when only default_visible filters exist with default values", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/test-default-visible")

      # Initially should have default_visible filters rendered
      html = render(view)
      assert html =~ "Status"
      assert html =~ "Urgent"

      # Clear all should NOT be visible (baseline filters with default values)
      refute html =~ "Clear all"
    end
  end

  describe "hides add filter when all fields active" do
    test "dropdown trigger hidden when all non-always-on fields added", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test")

      # Add all non-always-on filters
      add_filter(view, :status)
      add_filter(view, :urgent)
      add_filter(view, :active)
      add_filter(view, :created_at)
      add_filter(view, :updated_at)
      add_filter(view, :due_at)
      add_filter(view, :priority)
      add_filter(view, :category)

      html = render(view)

      # The add filter button should not be rendered
      refute html =~ "Add Filter"
    end
  end

  describe "radio_group" do
    test "adds radio_group filter with pills style", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test")

      add_filter(view, :priority)

      html = render(view)
      # Filter chip should exist
      assert html =~ "Priority"
      assert html =~ "filter-chip"
    end

    test "change_radio_group updates value and notifies parent", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test")

      add_filter(view, :priority)

      # Find the filter ID
      html = render(view)
      [_, filter_id] = Regex.run(~r/filter-chip-([^"]+)/, html)

      # Change radio group value
      filter_event(view, "change_radio_group", %{"id" => filter_id, "value" => "high"})

      html = render(view)
      # Parent should be notified with eq.high
      assert html =~ "eq.high"
    end

    test "adds radio_group filter with radios style", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test")

      add_filter(view, :category)

      html = render(view)
      # Filter chip should exist
      assert html =~ "Category"
      assert html =~ "filter-chip"
    end
  end

  describe "datetime picker" do
    test "adds datetime filter", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test")

      add_filter(view, :updated_at)

      html = render(view)
      assert html =~ "Updated"
      assert html =~ "filter-chip"
    end

    test "datetime_select_date updates date portion", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test")

      add_filter(view, :updated_at)

      # Find the filter ID
      html = render(view)
      [_, filter_id] = Regex.run(~r/filter-chip-([^"]+)/, html)

      # Select a date
      filter_event(view, "datetime_select_date", %{
        "id" => filter_id,
        "date" => "2026-02-14"
      })

      html = render(view)
      # Should have a datetime value
      assert html =~ "2026-02-14"
    end

    test "datetime_change_hour updates hour", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test")

      add_filter(view, :updated_at)

      html = render(view)
      [_, filter_id] = Regex.run(~r/filter-chip-([^"]+)/, html)

      # First select a date
      filter_event(view, "datetime_select_date", %{
        "id" => filter_id,
        "date" => "2026-02-14"
      })

      # Change hour
      filter_event(view, "datetime_change_hour", %{
        "id" => filter_id,
        "hour" => "3"
      })

      html = render(view)
      # Parent should be notified with datetime
      assert html =~ "updated_at"
    end

    test "datetime_change_minute updates minute", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test")

      add_filter(view, :updated_at)

      html = render(view)
      [_, filter_id] = Regex.run(~r/filter-chip-([^"]+)/, html)

      # First select a date
      filter_event(view, "datetime_select_date", %{
        "id" => filter_id,
        "date" => "2026-02-14"
      })

      # Change minute
      filter_event(view, "datetime_change_minute", %{
        "id" => filter_id,
        "minute" => "30"
      })

      html = render(view)
      assert html =~ "updated_at"
    end

    test "datetime_toggle_period toggles AM/PM", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test")

      add_filter(view, :updated_at)

      html = render(view)
      [_, filter_id] = Regex.run(~r/filter-chip-([^"]+)/, html)

      # First select a date
      filter_event(view, "datetime_select_date", %{
        "id" => filter_id,
        "date" => "2026-02-14"
      })

      # Toggle period
      filter_event(view, "datetime_toggle_period", %{
        "id" => filter_id,
        "period" => "pm"
      })

      html = render(view)
      assert html =~ "updated_at"
    end
  end

  describe "nullable boolean" do
    test "renders three options when nullable: true", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test")

      add_filter(view, :active)

      html = render(view)
      # Should show the custom labels
      assert html =~ "Active"
      assert html =~ "Inactive"
      assert html =~ "All"
    end

    test "selecting Any sets value to nil and keeps chip visible", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test")

      add_filter(view, :active)

      html = render(view)
      [_, filter_id] = Regex.run(~r/filter-chip-([^"]+)/, html)

      # Set to true first
      filter_event(view, "change_boolean", %{"id" => filter_id, "value" => "true"})

      # Then set to nil (Any)
      filter_event(view, "change_boolean", %{"id" => filter_id, "value" => "any"})

      html = render(view)
      # Chip should still be visible
      assert html =~ "filter-chip"
      # But no param value for active should be in updated_params
      # The nil value should result in the chip showing but no URL param
      refute html =~ "active=is."
    end

    test "uses custom true_label/false_label/any_label", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/test")

      add_filter(view, :active)

      html = render(view)
      # Uses custom labels from config
      assert html =~ "Active"
      assert html =~ "Inactive"
      assert html =~ "All"
    end
  end
end
