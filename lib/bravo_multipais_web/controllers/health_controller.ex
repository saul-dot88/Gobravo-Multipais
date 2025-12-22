defmodule BravoMultipaisWeb.HealthController do
  use BravoMultipaisWeb, :controller

  alias BravoMultipais.Repo

  @doc """
  Endpoint de health simple.

  - `status`: siempre "ok" si el controlador responde.
  - `db`: "ok" si la base responde a un `SELECT 1`, "error" si no.
  """
  def index(conn, _params) do
    db_status =
      case Repo.query("SELECT 1") do
        {:ok, _} -> "ok"
        {:error, _} -> "error"
      end

    json(conn, %{
      status: "ok",
      db: db_status
    })
  end
end
