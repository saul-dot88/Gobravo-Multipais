defmodule BravoMultipaisWeb.Router do
  use BravoMultipaisWeb, :router

  import BravoMultipaisWeb.UserAuth

  ## Pipelines

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BravoMultipaisWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :browser_auth do
    plug :require_authenticated_user
  end

  pipeline :backoffice do
    plug :backoffice_auth
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug BravoMultipaisWeb.ApiAuth
  end

  ## Backoffice UI – requiere login + rol

  scope "/", BravoMultipaisWeb do
    pipe_through [:browser, :browser_auth, :backoffice]

    live "/", ApplicationsLive, :index
  end

  ## API pública

  scope "/api", BravoMultipaisWeb do
    pipe_through :api

    post "/applications", ApplicationController, :create
    get "/applications/:id", ApplicationController, :show
    get "/applications", ApplicationController, :index
  end

  ## Mock webhooks

  scope "/mock", BravoMultipaisWeb do
    pipe_through :api

    post "/webhooks/applications", MockWebhookController, :receive
  end

  ## Dev (dashboard, mailbox)

  if Application.compile_env(:bravo_multipais, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BravoMultipaisWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Rutas que requieren usuario autenticado (settings)

  scope "/", BravoMultipaisWeb do
    pipe_through [:browser, :browser_auth]

    live_session :require_authenticated_user,
      on_mount: [{BravoMultipaisWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  ## Registro / login / magic link (públicas)

  scope "/", BravoMultipaisWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :current_user,
      on_mount: [{BravoMultipaisWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
  end

  ## Logout sin redirect_if_user_is_authenticated

  scope "/", BravoMultipaisWeb do
    pipe_through [:browser]

    delete "/users/log-out", UserSessionController, :delete
  end
end
