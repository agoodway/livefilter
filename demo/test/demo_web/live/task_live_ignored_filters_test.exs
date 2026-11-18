defmodule DemoWeb.TaskLiveIgnoredFiltersTest do
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Demo.{Projects, Tasks}

  test "a value the field cannot cast is ignored and named in a notice", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/tasks?estimated_hours=gt.lots")

    assert html =~ "Ignored filter"
    assert html =~ "estimated_hours"
  end

  test "a value the grammar rejects is ignored and named in a notice", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/tasks?urgent=is.maybe")

    assert html =~ "Ignored filter"
    assert html =~ "urgent"
  end

  test "an unknown field is ignored without a notice", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/tasks?bogus=eq.1")

    refute html =~ "Ignored filter"
  end

  test "valid filters show no notice", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/tasks?urgent=is.true")

    refute html =~ "Ignored filter"
  end

  test "an offset past the last row shows the past-end state", %{conn: conn} do
    {:ok, project} = Projects.create_project(%{name: "Alpha"})
    {:ok, _task} = Tasks.create_task(%{title: "One", status: "todo", project_id: project.id})

    {:ok, _lv, html} = live(conn, "/tasks?offset=999")

    assert html =~ "No results on this page"
  end
end
