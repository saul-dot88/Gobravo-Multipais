defmodule BravoMultipaisWeb.ApiAuthTest do
  use BravoMultipaisWeb.ConnCase, async: true

  alias BravoMultipaisWeb.ApiAuth

  describe "call/2" do
    test "halts with 401 when Authorization header is missing", %{conn: conn} do
      conn = ApiAuth.call(conn, ApiAuth.init([]))

      assert conn.halted
      assert conn.status == 401

      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "unauthorized"
      assert body["reason"] == "invalid_or_missing_token"
    end

    test "assigns current_api_client when token is valid", %{conn: conn} do
      claims = %{"sub" => "client-1", "role" => "backoffice"}
      token = ApiAuth.sign_token(claims)

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> ApiAuth.call(ApiAuth.init([]))

      refute conn.halted
      assert conn.status in [nil, 200]

      assert conn.assigns.current_api_client["sub"] == "client-1"
      assert conn.assigns.current_api_client["role"] == "backoffice"
    end
  end

  describe "require_role/2" do
    test "allows when role is in allowed_roles", %{conn: conn} do
      conn =
        conn
        |> assign(:current_api_client, %{"role" => "backoffice"})
        |> ApiAuth.require_role(["backoffice", "external"])

      refute conn.halted
      assert conn.status in [nil, 200]
    end

    test "returns 403 when role is missing", %{conn: conn} do
      conn = ApiAuth.require_role(conn, ["backoffice"])

      assert conn.halted
      assert conn.status == 403

      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "forbidden"
      # Si en el futuro agregas "reason", podrías asertar algo más aquí
    end

    test "returns 403 when role is not permitted", %{conn: conn} do
      conn =
        conn
        |> assign(:current_api_client, %{"role" => "external"})
        |> ApiAuth.require_role(["backoffice"])

      assert conn.halted
      assert conn.status == 403

      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "forbidden"
      # Igual aquí podríamos luego asertar un "reason" si lo defines
    end
  end

  describe "require_backoffice/1" do
    test "allows when role is backoffice", %{conn: conn} do
      conn =
        conn
        |> assign(:current_api_client, %{"role" => "backoffice"})
        |> ApiAuth.require_backoffice()

      refute conn.halted
      assert conn.status in [nil, 200]
    end

    test "forbids when role is external", %{conn: conn} do
      conn =
        conn
        |> assign(:current_api_client, %{"role" => "external"})
        |> ApiAuth.require_backoffice()

      assert conn.halted
      assert conn.status == 403

      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "forbidden"
    end
  end
end
