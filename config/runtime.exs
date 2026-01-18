import Config

# PHX_SERVER indica si el endpoint debe arrancar el servidor HTTP.
# En releases, lo normal es setear PHX_SERVER=true en el contenedor.
if System.get_env("PHX_SERVER") do
  config :bravo_multipais, BravoMultipaisWeb.Endpoint, server: true
end

if config_env() == :prod do
  # ─────────────────────────────────────────────
  # Base de datos
  # ─────────────────────────────────────────────

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 =
    if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :bravo_multipais, BravoMultipais.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # ─────────────────────────────────────────────
  # Secret key base
  # ─────────────────────────────────────────────

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # ─────────────────────────────────────────────
  # Endpoint (URL externa + puerto interno)
  # ─────────────────────────────────────────────
  #
  # URL_* describe cómo se expone hacia fuera (Ingress / LB),
  # PORT describe el puerto interno donde escucha el contenedor.

  host =
    System.get_env("URL_HOST") ||
      System.get_env("PHX_HOST") ||
      "example.com"

  url_scheme = System.get_env("URL_SCHEME") || "https"
  url_port = String.to_integer(System.get_env("URL_PORT") || "443")

  http_port = String.to_integer(System.get_env("PORT") || "4000")

  config :bravo_multipais, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :bravo_multipais, BravoMultipaisWeb.Endpoint,
    url: [host: host, port: url_port, scheme: url_scheme]

  bind_ip =
    if System.get_env("PHX_IPV6") in ~w(true 1) do
      {0, 0, 0, 0, 0, 0, 0, 0}
    else
      {0, 0, 0, 0}
    end

  config :bravo_multipais, BravoMultipaisWeb.Endpoint,
    url: [host: host, port: url_port, scheme: url_scheme],
    http: [
      ip: bind_ip,
      port: http_port
    ],
    secret_key_base: secret_key_base

  # ─────────────────────────────────────────────
  # Configuración de webhooks (WebhookNotifier)
  # ─────────────────────────────────────────────

  skip_webhooks =
    case String.downcase(System.get_env("SKIP_WEBHOOKS") || "false") do
      "1" -> true
      "true" -> true
      _ -> false
    end

  webhook_url =
    System.get_env("WEBHOOK_URL") ||
      "http://localhost:4001/webhooks/applications"

  config :bravo_multipais,
    skip_webhooks: skip_webhooks,
    webhook_url: webhook_url
end
