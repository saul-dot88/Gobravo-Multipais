defmodule BravoMultipaisWeb.HealthControllerTest do
  use BravoMultipaisWeb.ConnCase, async: true

  test "GET /api/health devuelve status ok y estado de la BD", %{conn: conn} do
    conn = get(conn, ~p"/api/health")

    assert %{"status" => "ok", "db" => db_status} = json_response(conn, 200)
    assert db_status in ["ok", "error"]
  end
end
