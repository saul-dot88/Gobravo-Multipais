defmodule BravoMultipaisWeb.SessionController do
  use BravoMultipaisWeb, :controller

  @doc """
  Pantalla de login para backoffice.
  """
  def new(conn, _params) do
    render(conn, :new)
  end

  @doc """
  Procesa el login. Para el MVP, solo validamos un password fijo.
  """
  def create(conn, %{"password" => password}) do
    expected =
      Application.get_env(:bravo_multipais, :backoffice_password, "secret123")

    if password == expected do
      user = %{id: "backoffice", role: "backoffice"}

      conn
      |> put_session(:backoffice_user, user)
      |> put_flash(:info, "Bienvenido al panel de crédito multipaís.")
      |> redirect(to: "/")
    else
      conn
      |> put_flash(:error, "Credenciales inválidas.")
      |> render(:new)
    end
  end

  @doc """
  Cierra sesión y limpia la sesión.
  """
  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "Sesión cerrada.")
    |> redirect(to: "/login")
  end
end
