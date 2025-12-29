defmodule BravoMultipaisWeb.Router do
  use BravoMultipaisWeb, :router

  import BravoMultipaisWeb.UserAuth

  # Sólo alias si quieres, pero vamos a usar nombres completos para evitar confusiones
  # alias OpenApiSpex.Plug.{PutApiSpec, RenderSpec}

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

  # Puedes dejar aquí PutApiSpec o sólo en el Endpoint; las dos cosas funcionan.
  pipeline :api_public do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: BravoMultipaisWeb.ApiSpec
  end

  pipeline :api_protected do
    plug :accepts, ["json"]
    plug BravoMultipaisWeb.ApiAuth
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug BravoMultipaisWeb.ApiAuth
  end

  ## Backoffice UI

  scope "/", BravoMultipaisWeb do
    pipe_through [:browser, :browser_auth, :backoffice]

    live "/", ApplicationsLive, :index
  end

  ## Métricas (PromEx)

  scope "/" do
    pipe_through :api_public

    forward "/metrics", PromEx.Plug, prom_ex_module: BravoMultipais.PromEx
  end

  ## API pública + OpenAPI JSON
  ## 👇 OJO: este scope NO tiene módulo, así evitamos el prefijo BravoMultipaisWeb.

  scope "/api" do
    pipe_through :api_public

    get "/health", BravoMultipaisWeb.HealthController, :index
    get "/openapi", OpenApiSpex.Plug.RenderSpec, []   # ← módulo completo del plug externo
  end

  ## API pública protegida (business endpoints)

  scope "/api", BravoMultipaisWeb do
    pipe_through :api_protected

    post "/applications", ApplicationController, :create
    get  "/applications/:id", ApplicationController, :show
    get  "/applications", ApplicationController, :index
  end

  ## Mock webhooks

  scope "/mock", BravoMultipaisWeb do
    pipe_through :api

    post "/webhooks/applications", MockWebhookController, :receive
  end

  ## Dev (dashboard, mailbox, swagger)

  if Application.compile_env(:bravo_multipais, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BravoMultipaisWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview

      # Swagger UI nativo de open_api_spex
      forward "/swagger", OpenApiSpex.Plug.SwaggerUI,
        path: "/api/openapi",
        title: "BravoMultipais API"
    end
  end

  ## Settings

  scope "/", BravoMultipaisWeb do
    pipe_through [:browser, :browser_auth]

    live_session :require_authenticated_user,
      on_mount: [{BravoMultipaisWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  ## Registro / login

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

  ## Logout

  scope "/", BravoMultipaisWeb do
    pipe_through [:browser]

    delete "/users/log-out", UserSessionController, :delete
  end
end
