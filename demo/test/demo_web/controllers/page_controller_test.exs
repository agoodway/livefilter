defmodule DemoWeb.PageControllerTest do
  use DemoWeb.ConnCase

  test "GET / renders the LiveFilter task explorer", %{conn: conn} do
    conn = get(conn, ~p"/")
    body = html_response(conn, 200)
    assert body =~ "LiveFilter"
    assert body =~ "Tasks"
  end
end
