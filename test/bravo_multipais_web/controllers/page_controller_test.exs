defmodule BravoMultipaisWeb.PageControllerTest do
  use BravoMultipaisWeb.ConnCase

  test "GET / redirects to login when user is not authenticated", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn, 302) == ~p"/users/log-in"
  end
end
