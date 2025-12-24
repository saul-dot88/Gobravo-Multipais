defmodule BravoMultipais.PromEx do
  @moduledoc """
  PromEx collector para BravoMultipais.

  Expone métricas de:

    * BEAM / VM
    * Aplicación (uptime, versión, etc.)
    * Phoenix (endpoint, router)
    * Phoenix LiveView
    * Ecto (Repo)
    * Oban (queues y jobs)
  """

  use PromEx, otp_app: :bravo_multipais

  @impl true
  def plugins do
    [
      # Métricas básicas de app y BEAM
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,

      # Phoenix + LiveView
      {PromEx.Plugins.Phoenix,
       router: BravoMultipaisWeb.Router, endpoint: BravoMultipaisWeb.Endpoint},
      {PromEx.Plugins.PhoenixLiveView, endpoint: BravoMultipaisWeb.Endpoint},

      # Ecto
      {PromEx.Plugins.Ecto, repos: [BravoMultipais.Repo]},

      # Oban
      {PromEx.Plugins.Oban, oban_apps: [bravo_multipais: [Oban]]}
    ]
  end

  @impl true
  def dashboards do
    # Para el reto no necesitas subir dashboards a Grafana;
    # puedes dejar esto vacío y documentar en el README que
    # PromEx está listo para integrarse con Grafana si se requiere.
    []
  end
end
