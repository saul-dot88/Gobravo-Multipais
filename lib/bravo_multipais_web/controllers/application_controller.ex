defmodule BravoMultipaisWeb.ApplicationController do
  use BravoMultipaisWeb, :controller

  alias BravoMultipais.CreditApplications
  alias BravoMultipais.CreditApplications.Commands
  alias BravoMultipais.CreditApplications.Queries

  # POST /api/applications
  def create(conn, params) do
    case Commands.create_application(params) do
      {:ok, app} ->
        conn
        |> put_status(:created)
        |> json(%{
          id: app.id,
          country: app.country,
          full_name: app.full_name,
          status: app.status,
          bank_profile: app.bank_profile
        })

      {:error, {:validation_error, type, detail}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_error", type: type, detail: inspect(detail)})

      {:error, {:integration_error, type, detail}} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{error: "integration_error", type: type, detail: inspect(detail)})

      {:error, {:changeset_error, changeset}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid_data", detail: inspect(changeset.errors)})

      {:error, other} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "unexpected_error", detail: inspect(other)})
    end
  end

  # GET /api/applications/:id
  def show(conn, %{"id" => id}) do
    case Queries.get_application(id) do
      nil ->
        send_resp(conn, :not_found, "")

      app ->
        json(conn, %{
          id: app.id,
          country: app.country,
          full_name: app.full_name,
          document: app.document,
          amount: app.amount,
          monthly_income: app.monthly_income,
          status: app.status,
          bank_profile: app.bank_profile,
          risk_score: app.risk_score,
          inserted_at: app.inserted_at
        })
    end
  end

  # GET /api/applications?country=ES&status=APPROVED
  def index(conn, params) do
    apps = Queries.list_applications(params)
    json(conn, apps)
  end
end
