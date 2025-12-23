defmodule BravoMultipaisWeb.UserAuth do
  @moduledoc """
  Helpers de autenticación para la capa web: login/logout, carga del usuario
  actual y enforcement de roles (por ejemplo, backoffice).
  """
  use BravoMultipaisWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias BravoMultipais.Accounts
  alias BravoMultipais.Accounts.Scope
  alias BravoMultipais.Accounts.User
  alias BravoMultipaisWeb.Router.Helpers, as: Routes
  alias LiveView

  # Make the remember me cookie valid for 14 days. This should match
  # the session validity setting in UserToken.
  @max_cookie_age_in_days 14
  @remember_me_cookie "_bravo_multipais_web_user_remember_me"
  @remember_me_options [
    sign: true,
    max_age: @max_cookie_age_in_days * 24 * 60 * 60,
    same_site: "Lax"
  ]

  # How old the session token should be before a new one is issued. When a request is made
  # with a session token older than this value, then a new session token will be created
  # and the session and remember-me cookies (if set) will be updated with the new token.
  # Lowering this value will result in more tokens being created by active users. Increasing
  # it will result in less time before a session token expires for a user to get issued a new
  # token. This can be set to a value greater than `@max_cookie_age_in_days` to disable
  # the reissuing of tokens completely.
  @session_reissue_age_in_days 7

  @doc """
  Logs the user in.

  Redirects to the session's `:user_return_to` path
  or falls back to the `signed_in_path/1`.
  """
  def log_in_user(conn, user, params \\ %{}) do
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> create_or_extend_session(user, params)
    |> redirect(to: user_return_to || signed_in_path(conn))
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      BravoMultipaisWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session(nil)
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: ~p"/")
  end

  @doc """
  Authenticates the user by looking into the session and remember me token.

  Will reissue the session token if it is older than the configured age.
  """

  def fetch_current_scope_for_user(conn, _opts) do
    user =
      conn
      |> get_session(:user_token)
      |> Accounts.get_user_by_session_token()

    scope = Scope.for_user(user, user && user.authenticated_at)

    conn
    |> assign(:current_user, user)
    |> assign(:current_scope, scope)
  end

  def fetch_current_user(conn, _opts) do
    {user_token, conn} = ensure_user_token(conn)
    user = user_token && Accounts.get_user_by_session_token(user_token)
    assign(conn, :current_user, user)
  end

  defp ensure_user_token(conn) do
    case get_session(conn, :user_token) do
      nil ->
        ensure_user_token_from_remember_me(conn)

      token ->
        {token, conn}
    end
  end

  defp ensure_user_token_from_remember_me(conn) do
    conn = fetch_cookies(conn, signed: [@remember_me_cookie])

    case conn.cookies[@remember_me_cookie] do
      nil ->
        {nil, conn}

      token ->
        conn =
          conn
          |> put_token_in_session(token)
          |> put_session(:user_remember_me, true)

        {token, conn}
    end
  end

  # Reissue the session token if it is older than the configured reissue age.
  defp maybe_reissue_user_session_token(conn, user, token_inserted_at) do
    token_age = DateTime.diff(DateTime.utc_now(:second), token_inserted_at, :day)

    if token_age >= @session_reissue_age_in_days do
      create_or_extend_session(conn, user, %{})
    else
      conn
    end
  end

  # This function is the one responsible for creating session tokens
  # and storing them safely in the session and cookies. It may be called
  # either when logging in, during sudo mode, or to renew a session which
  # will soon expire.
  #
  # When the session is created, rather than extended, the renew_session
  # function will clear the session to avoid fixation attacks. See the
  # renew_session function to customize this behaviour.
  defp create_or_extend_session(conn, user, params) do
    token = Accounts.generate_user_session_token(user)
    remember_me = get_session(conn, :user_remember_me)

    conn
    |> renew_session(user)
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params, remember_me)
  end

  # Do not renew session if the user is already logged in
  # to prevent CSRF errors or data being lost in tabs that are still open
  defp renew_session(conn, user) when conn.assigns.current_scope.user.id == user.id do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn, _user) do
  #       delete_csrf_token()
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn, _user) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}, _),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, token, _params, true),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, _token, _params, _), do: conn

  defp write_remember_me_cookie(conn, token) do
    conn
    |> put_session(:user_remember_me, true)
    |> put_resp_cookie(@remember_me_cookie, token, @remember_me_options)
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, user_session_topic(token))
  end

  @doc """
  Disconnects existing sockets for the given tokens.
  """
  def disconnect_sessions(tokens) do
    Enum.each(tokens, fn %{token: token} ->
      BravoMultipaisWeb.Endpoint.broadcast(user_session_topic(token), "disconnect", %{})
    end)
  end

  defp user_session_topic(token), do: "users_sessions:#{Base.url_encode64(token)}"

  @doc """
  Handles mounting and authenticating the current_scope in LiveViews.

  ## `on_mount` arguments

    * `:mount_current_scope` - Assigns current_scope
      to socket assigns based on user_token, or nil if
      there's no user_token or no matching user.

    * `:require_authenticated` - Authenticates the user from the session,
      and assigns the current_scope to socket assigns based
      on user_token.
      Redirects to login page if there's no logged user.

  ## Examples

  Use the `on_mount` lifecycle macro in LiveViews to mount or authenticate
  the `current_scope`:

      defmodule BravoMultipaisWeb.PageLive do
        use BravoMultipaisWeb, :live_view

        on_mount {BravoMultipaisWeb.UserAuth, :mount_current_scope}
        ...
      end

  Or use the `live_session` of your router to invoke the on_mount callback:

      live_session :authenticated, on_mount: [{BravoMultipaisWeb.UserAuth, :require_authenticated}] do
        live "/profile", ProfileLive, :index
      end
  """
  # Para sesiones que solo necesitan saber si hay usuario + rol
  def on_mount(:mount_current_scope, _params, session, socket) do
    socket =
      socket
      |> LiveView.Utils.assign_new(:current_user, fn ->
        case session["user_token"] do
          nil -> nil
          token -> Accounts.get_user_by_session_token(token)
        end
      end)
      |> LiveView.Utils.assign_new(:current_scope, fn %{current_user: user} ->
        Scope.for_user(user, user && user.authenticated_at)
      end)

    {:cont, socket}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      {:cont, socket}
    else
      socket =
        socket
        |> LiveView.put_flash(:error, "You must log in to access this page.")
        |> LiveView.redirect(to: ~p"/users/log-in")

      {:halt, socket}
    end
  end

  def on_mount(:require_sudo_mode, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope &&
         socket.assigns.current_scope.user &&
         Accounts.sudo_mode?(socket.assigns.current_scope.user, -10) do
      {:cont, socket}
    else
      socket =
        socket
        |> LiveView.put_flash(:error, "You must re-authenticate to access this page.")
        |> LiveView.redirect(to: ~p"/users/log-in")

      {:halt, socket}
    end
  end

  def on_mount(:require_backoffice, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    case socket.assigns[:current_scope] do
      %Scope{user: %User{}, role: "backoffice"} ->
        # Usuario logueado y con rol correcto → dejamos continuar
        {:cont, socket}

      nil ->
        # Sin scope → lo tratamos como no autenticado
        socket =
          socket
          |> LiveView.put_flash(
            :error,
            "Debes iniciar sesión para acceder al backoffice."
          )
          |> LiveView.redirect(to: ~p"/users/log-in")

        {:halt, socket}

      %Scope{} ->
        # Autenticado pero sin rol backoffice
        socket =
          socket
          |> LiveView.put_flash(:error, "No tienes permisos para acceder al backoffice.")
          |> LiveView.redirect(to: ~p"/")

        {:halt, socket}
    end
  end

  defp mount_current_scope(socket, session) do
    Phoenix.Component.assign_new(socket, :current_scope, fn ->
      user =
        if user_token = session["user_token"] do
          Accounts.get_user_by_session_token(user_token)
        else
          nil
        end

      # usamos el helper Scope.for_user/2 para inyectar authenticated_at si viene
      Scope.for_user(user, user && user.authenticated_at)
    end)
  end

  @doc """
  Plug para restringir acceso a usuarios con rol `backoffice`.

  - Si no hay @current_scope (no autenticado), redirige a login.
  - Si el rol no es "backoffice", responde 403.
  - Si todo bien, deja pasar el request.
  """
  def backoffice_auth(conn, _opts) do
    scope = conn.assigns[:current_scope]

    cond do
      # Sin usuario autenticado → lo mandamos a log in
      is_nil(scope) or is_nil(scope.user) ->
        conn
        |> Phoenix.Controller.put_flash(
          :error,
          "Debes iniciar sesión para acceder al backoffice."
        )
        |> Phoenix.Controller.redirect(to: ~p"/users/log-in")
        |> Plug.Conn.halt()

      # Usuario autenticado pero sin rol backoffice → 403, NO redirigimos a login
      scope.role != "backoffice" ->
        conn
        |> Plug.Conn.put_status(:forbidden)
        |> Phoenix.Controller.put_view(BravoMultipaisWeb.ErrorHTML)
        |> Phoenix.Controller.render("403.html")
        |> Plug.Conn.halt()

      # OK: usuario autenticado + rol correcto
      true ->
        conn
    end
  end

  # Si el usuario ya está autenticado, que NO vea el login
  def redirect_if_user_is_authenticated(conn, _opts) do
    current_scope = conn.assigns[:current_scope]
    current_user = conn.assigns[:current_user]

    if current_scope || current_user do
      conn
      |> redirect(to: ~p"/")
      |> halt()
    else
      conn
    end
  end

  # Para proteger rutas que requieren login
  def require_authenticated_user(conn, _opts) do
    current_scope = conn.assigns[:current_scope]
    current_user = conn.assigns[:current_user]

    if current_scope || current_user do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log-in")
      |> halt()
    end
  end

  @doc "Returns the path to redirect to after log in."
  def signed_in_path(_conn) do
    # Siempre mandamos al home del backoffice
    ~p"/"
  end

  def signed_in_path(_), do: ~p"/"

  @doc """
  Plug for routes that require the user to be authenticated.
  """
  def require_authenticated_user(conn, _opts) do
    current_scope = conn.assigns[:current_scope]
    current_user = conn.assigns[:current_user]

    if current_scope || current_user do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log-in")
      |> halt()
    end
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn
end
