defmodule BravoMultipaisWeb.ApiAuth do
  @moduledoc """
  Auth sencilla para API usando `Authorization: Bearer <token>`.

  - Token firmado con `Phoenix.Token` (HMAC + expiración).
  - En `assigns.current_api_client` se deja algo como: `%{sub: "...", role: "backoffice"}`.
  - Incluye helpers para validar roles (backoffice / external) y responder 401 / 403 en JSON.
  """

  import Plug.Conn

  @behaviour Plug

  # 24 horas
  @token_max_age 86_400

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- verify_token(token) do
      conn
      |> assign(:current_api_client, claims)
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          :unauthorized,
          Jason.encode!(%{
            error: "unauthorized",
            reason: "invalid_or_missing_token"
          })
        )
        |> halt()
    end
  end

  # --- helpers para uso desde controladores ---

  @doc """
  Verifica que el cliente tenga alguno de los roles permitidos.

  Ejemplo:
      ApiAuth.require_role(conn, ["backoffice", "admin"])
  """
  def require_role(conn, allowed_roles) when is_list(allowed_roles) do
    role =
      conn.assigns[:current_api_client]
      |> get_in_role()

    cond do
      is_nil(role) ->
        forbid(conn, :missing_role)

      role in allowed_roles ->
        conn

      true ->
        forbid(conn, {:insufficient_permissions, role, allowed_roles})
    end
  end

  @doc """
  Conveniencia para flujos típicos:
    - `require_backoffice/2`
    - `require_external/2`
  """

  def require_backoffice(conn, _opts \\ []) do
    require_role(conn, ["backoffice"])
  end

  def require_external(conn, _opts \\ []) do
    require_role(conn, ["external"])
  end

  # --- generación y verificación del token ---

  defp verify_token(token) do
    Phoenix.Token.verify(
      BravoMultipaisWeb.Endpoint,
      "api_auth",
      token,
      max_age: @token_max_age
    )
  end

  @doc """
  Helper para firmar un token en dev/iex y probar la API.

      iex> BravoMultipaisWeb.ApiAuth.sign_token(%{sub: "dev-user", role: "backoffice"})
  """
  def sign_token(claims) when is_map(claims) do
    Phoenix.Token.sign(BravoMultipaisWeb.Endpoint, "api_auth", claims)
  end

  # --- internos ---

  defp get_in_role(nil), do: nil

  defp get_in_role(claims) when is_map(claims) do
    Map.get(claims, "role") || Map.get(claims, :role)
  end

  defp forbid(conn, :missing_role) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      :forbidden,
      Jason.encode!(%{
        error: "forbidden",
        reason: "missing_role_claim"
      })
    )
    |> halt()
  end

  defp forbid(conn, {:insufficient_permissions, current_role, allowed}) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      :forbidden,
      Jason.encode!(%{
        error: "forbidden",
        reason: "insufficient_permissions",
        current_role: current_role,
        allowed_roles: allowed
      })
    )
    |> halt()
  end
end
