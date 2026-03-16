defmodule ClaimViewerWeb.PageControllerTest do
  use ClaimViewerWeb.ConnCase

  test "GET / renders dashboard", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "DASHBOARD"
  end
end
