defmodule BravoMultipaisWeb.ApplicationController do
  use BravoMultipaisWeb, :controller

  alias BravoMultipais.CreditApplications
  alias BravoMultipais.CreditApplications.Application

  action_fallback BravoMultipaisWeb.FallbackController

  # GET /api/applications
  def index(conn, params) do
    applications = CreditApplications.list_applications(params || %{})

    conn
    |> put_status(:ok)
    |> render(:index, applications: applications)
  end

  # GET /api/applications/:id
  def show(conn, %{"id" => id}) do
    case CreditApplications.get_application(id) do
      nil ->
        {:error, :not_found}

      %Application{} = app ->
        conn
        |> put_status(:ok)
        |> render(:show, application: app)
    end
  end

  # POST /api/applications
  def create(conn, params) do
    with {:ok, %Application{} = app} <- CreditApplications.create_application(params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/applications/#{app.id}")
      |> render(:show, application: app)
    end
  end
end
