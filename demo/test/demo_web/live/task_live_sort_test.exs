defmodule DemoWeb.TaskLiveSortTest do
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "clicking a column header sorts and reflects in the URL + aria-sort", %{conn: conn} do
    {:ok, lv, _html} = live(conn, "/tasks")

    lv
    |> element(~s(button[phx-click="lf_sort"][phx-value-field="title"]))
    |> render_click()

    assert_patch(lv) =~ "order=title"
    assert render(lv) =~ ~s(aria-sort="ascending")
  end

  test "an order= URL param renders the matching header as sorted", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/tasks?order=due_date.desc")

    assert html =~ ~s(aria-sort="descending")
  end

  test "a numeric column header sorts descending first (its declared default)", %{conn: conn} do
    {:ok, lv, _html} = live(conn, "/tasks")

    lv
    |> element(~s(button[phx-click="lf_sort"][phx-value-field="estimated_hours"]))
    |> render_click()

    path = assert_patch(lv)
    assert path =~ "order=estimated_hours.desc"
    assert render(lv) =~ ~s(aria-sort="descending")
  end
end
