defmodule BravoMultipais.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Oban, Application.fetch_env!(:bravo_multipais, Oban)},
      BravoMultipaisWeb.Telemetry,
      BravoMultipais.Repo,
      {DNSCluster, query: Application.get_env(:bravo_multipais, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BravoMultipais.PubSub},
      # Start a worker by calling: BravoMultipais.Worker.start_link(arg)
      # {BravoMultipais.Worker, arg},
      # Start to serve requests, typically the last entry
      BravoMultipaisWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BravoMultipais.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BravoMultipaisWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
