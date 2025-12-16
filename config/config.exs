# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :bravo_multipais, :scopes,
  user: [
    default: true,
    module: BravoMultipais.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: BravoMultipais.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :bravo_multipais,
  ecto_repos: [BravoMultipais.Repo],
  generators: [timestamp_type: :utc_datetime]

config :bravo_multipais,
  backoffice_password: System.get_env("BACKOFFICE_PASSWORD") || "secret123"

# Configures the endpoint
config :bravo_multipais, BravoMultipaisWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BravoMultipaisWeb.ErrorHTML, json: BravoMultipaisWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: BravoMultipais.PubSub,
  live_view: [signing_salt: "P2I3CwoV"]


config :bravo_multipais, BravoMultipais.Finch,
  pools: %{
    default: [size: 10, count: 1]
  }

config :bravo_multipais,
  webhook_url: "http://localhost:4000/mock/webhooks/applications"

config :bravo_multipais, Oban,
  repo: BravoMultipais.Repo,
  queues: [risk: 10, webhook: 5],
  plugins: [Oban.Plugins.Pruner]


# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :bravo_multipais, BravoMultipais.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  bravo_multipais: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  bravo_multipais: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
