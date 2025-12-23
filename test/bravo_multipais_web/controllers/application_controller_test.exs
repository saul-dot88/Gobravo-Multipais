defmodule BravoMultipaisWeb.ApplicationControllerTest do
  @moduledoc false

  use BravoMultipaisWeb.ConnCase, async: true

  alias BravoMultipais.CreditApplications
  alias BravoMultipais.CreditApplications.Application
  alias BravoMultipaisWeb.ApiAuth

  @valid_es_params %{
    "country" => "ES",
    "full_name" => "Juan Pérez",
    "document_value" => "12345678Z",
    "amount" => "5000",
    "monthly_income" => "2000"
  }

  @low_income_es_params %{
    "country" => "ES",
    "full_name" => "Juan Pérez",
    "document_value" => "12345678Z",
    "amount" => "20000",
    # Debajo del umbral para disparar :income_too_low
    "monthly_income" => "200"
  }

  # --- setup: siempre meter un token de backoffice en el header ---

  setup %{conn: conn} do
    conn = put_backoffice_token(conn)
    {:ok, conn: conn}
  end

  defp put_backoffice_token(conn) do
    claims = %{
      "sub" => "backoffice-user-1",
      "role" => "backoffice"
    }

    token = ApiAuth.sign_token(claims)

    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  # --- tests POST /api/applications ---

  test "POST /api/applications create/2 returns 201 and public json when params are valid",
       %{conn: conn} do
    conn =
      post(conn, ~p"/api/applications", @valid_es_params)

    assert %{"data" => resp} = json_response(conn, 201)

    assert resp["country"] == "ES"
    assert resp["full_name"] == "Juan Pérez"
    assert resp["document"] == %{"dni" => "12345678Z"}
    assert resp["amount"] == "5000"
    assert resp["monthly_income"] == "2000"
    assert resp["status"] == "PENDING_RISK"
    assert resp["risk_score"] == nil
  end

  test "POST /api/applications create/2 returns 422 and policy_error when income is too low",
       %{conn: conn} do
    conn =
      post(conn, ~p"/api/applications", @low_income_es_params)

    assert %{"error" => "policy_error", "reason" => reason} =
             json_response(conn, 422)

    # Sólo verificamos que viene el atom en el inspect
    assert reason =~ "income_too_low"
  end

  # --- tests GET /api/applications (index) ---

  test "GET /api/applications index/2 returns public list of applications",
       %{conn: conn} do
    {:ok, app1} = CreditApplications.create_application(@valid_es_params)

    {:ok, app2} =
      CreditApplications.create_application(%{
        @valid_es_params
        | "document_value" => "98765432M"
      })

    conn = get(conn, ~p"/api/applications")

    assert %{"data" => list} = json_response(conn, 200)
    assert length(list) >= 2

    ids = Enum.map(list, & &1["id"])

    assert app1.id in ids
    assert app2.id in ids
  end

  test "GET /api/applications index/2 respects filters (por país, al menos)",
       %{conn: conn} do
    # ES
    {:ok, _es_app} =
      CreditApplications.create_application(@valid_es_params)

    # IT
    {:ok, _it_app} =
      CreditApplications.create_application(%{
        "country" => "IT",
        "full_name" => "Marco Bianchi",
        "document_value" => "BNCMRC80A01F205Y",
        "amount" => "5000",
        "monthly_income" => "2000"
      })

    conn =
      get(conn, ~p"/api/applications", %{"country" => "IT"})

    assert %{"data" => list} = json_response(conn, 200)
    assert Enum.all?(list, &(&1["country"] == "IT"))
  end

  # --- tests GET /api/applications/:id (show) ---

  test "GET /api/applications/:id show/2 returns 200 and public json when found",
       %{conn: conn} do
    {:ok, app} = CreditApplications.create_application(@valid_es_params)

    conn = get(conn, ~p"/api/applications/#{app.id}")

    assert %{"data" => resp} = json_response(conn, 200)
    assert is_map(resp["document"])
    assert resp["document"]["raw"] == "12345678Z"
    assert resp["document"]["dni"] == "12345678Z"
  end

  test "GET /api/applications/:id show/2 returns 404 when not found",
       %{conn: conn} do
    unknown_id = Ecto.UUID.generate()

    conn = get(conn, ~p"/api/applications/#{unknown_id}")

    assert %{"error" => "not_found"} = json_response(conn, 404)
  end
end
