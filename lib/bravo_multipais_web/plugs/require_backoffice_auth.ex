defmodule BravoMultipaisWeb.Plugs.RequireBackofficeAuth do
  @moduledoc """
  Plug sencillo para requerir autenticación de backoffice
  antes de acceder al panel LiveView.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2, put_flash: 3]

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :backoffice_user) do
      nil ->
        conn
        |> put_flash(:error, "Debes iniciar sesión para acceder al panel.")
        |> redirect(to: "/login")
        |> halt()

      user ->
        assign(conn, :current_user, user)
    end
  end
end
