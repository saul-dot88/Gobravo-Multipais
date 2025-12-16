defmodule BravoMultipaisWeb.ApplicationController do
  use BravoMultipaisWeb, :controller

  alias BravoMultipais.CreditApplications
  alias BravoMultipaisWeb.ApiAuth

  # Autorización por acción
  plug :require_backoffice when action in [:index, :show]
  plug :require_creator when action in [:create]

  # GET /api/applications
  def index(conn, params) do
    apps = CreditApplications.list_applications(params)
    json(conn, %{data: apps})
  end

  # GET /api/applications/:id
  def show(conn, %{"id" => id}) do
    case CreditApplications.get_application_public(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found", resource: "application", id: id})

      app ->
        json(conn, %{data: app})
    end
  end

  # POST /api/applications
  def create(conn, params) do
    case CreditApplications.create_application(params) do
      {:ok, app} ->
        conn
        |> put_status(:created)
        |> json(%{data: app})

      {:error, {:business_rules_failed, reason}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "business_rules_failed",
          reason: to_string(reason)
        })

      {:error, {:validation_failed, details}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "validation_failed",
          details: details
        })

      {:error, :bank_integration_failed} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{
          error: "bank_integration_failed",
          message: "Error al consultar el proveedor bancario"
        })

      {:error, other} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          error: "internal_error",
          reason: inspect(other)
        })
    end
  end

  # --- plugs privados ---

  defp require_backoffice(conn, _opts) do
    ApiAuth.require_backoffice(conn)
  end

  defp require_creator(conn, _opts) do
    # Ejemplo: dejar que backoffice Y external creen
    ApiAuth.require_role(conn, ["backoffice", "external"])
  end
end
