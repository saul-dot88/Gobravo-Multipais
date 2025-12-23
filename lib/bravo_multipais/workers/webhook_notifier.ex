defmodule BravoMultipais.Workers.WebhookNotifier do
  @moduledoc """
  Worker que envía un webhook externo cuando cambia una solicitud de crédito.

  En entorno de test **no** hace llamadas HTTP reales, sólo hace log y termina en :ok.
  """

  use Oban.Worker,
    queue: :webhooks,
    max_attempts: 5

  alias BravoMultipais.Repo
  alias BravoMultipais.CreditApplications.Application
  alias BravoMultipaisWeb.Endpoint

  require Logger

  @topic "applications"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"application_id" => application_id}}) do
    app = Repo.get!(Application, application_id)

    if skip_webhooks?() do
      Logger.debug("Skipping webhook (config skip_webhooks=true)",
        application_id: app.id,
        status: app.status,
        risk_score: app.risk_score
      )

      :ok
    else
      do_send_webhook(app)
    end
  end

  defp skip_webhooks? do
    Elixir.Application.get_env(:bravo_multipais, :skip_webhooks, false)
  end

  @doc """
  Helper para encolar el job del webhook desde cualquier parte del dominio.

  Ejemplo:

      WebhookNotifier.enqueue(app.id)
  """
  @spec enqueue(Ecto.UUID.t()) :: :ok | {:error, term()}
  def enqueue(application_id) when is_binary(application_id) do
    %{"application_id" => application_id}
    |> __MODULE__.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # --- implementación real para dev/prod ---

  defp do_send_webhook(app) do
    url = webhook_url()

    payload = %{
      application_id: app.id,
      status: app.status,
      risk_score: app.risk_score,
      country: app.country
    }

    body = Jason.encode!(payload)

    headers = [
      {"content-type", "application/json"},
      {"x-bravo-event", "credit_application.updated"}
    ]

    Logger.info("Enviando webhook de aplicación",
      application_id: app.id,
      status: app.status,
      url: url
    )

    with {:ok, resp} <-
           Finch.build(:post, url, headers, body)
           |> Finch.request(BravoMultipais.Finch) do
      case resp.status do
        status when status in 200..299 ->
          Logger.info("Webhook enviado correctamente",
            application_id: app.id,
            status: app.status,
            http_status: status
          )

          # refrescar UI igual que EvaluateRisk
          Endpoint.broadcast(@topic, "status_changed", %{
            id: app.id,
            status: app.status,
            risk_score: app.risk_score,
            at: DateTime.utc_now()
          })

          Endpoint.broadcast(@topic, "webhook_resent", %{
            application_id: app.id,
            at: DateTime.utc_now()
          })

          :ok

        status ->
          Logger.error("Webhook respondió con error",
            application_id: app.id,
            http_status: status,
            response: inspect(resp)
          )

          {:error, {:http_error, status}}
      end
    else
      {:error, reason} ->
        Logger.error("Error HTTP enviando webhook",
          application_id: app.id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp webhook_url do
    # Usamos Elixir.Application para no chocar con el alias Application del schema
    Elixir.Application.get_env(
      :bravo_multipais,
      :webhook_url,
      "http://localhost:4001/webhooks/applications"
    )
  end
end
