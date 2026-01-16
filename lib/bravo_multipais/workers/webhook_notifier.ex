defmodule BravoMultipais.Workers.WebhookNotifier do
  @moduledoc """
  Worker que envía un webhook externo cuando cambia una solicitud de crédito.

  Política de reintentos:
    * 2xx -> :ok
    * 4xx -> :discard (error permanente)
    * 5xx / timeout / network -> {:error, ...} (retry por Oban)

  En entorno de test NO hace llamadas HTTP reales (solo log y :ok).
  """

  use Oban.Worker,
    queue: :webhooks,
    max_attempts: 5,
    unique: [
      fields: [:worker, :queue, :args],
      keys: [:application_id],
      period: 60,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias BravoMultipais.CreditApplications.Application
  alias BravoMultipais.Repo
  alias BravoMultipaisWeb.Endpoint

  require Logger

  @topic "applications"
  @event_type "application.status_changed"
  @event_version "v1"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"application_id" => application_id}}) do
    app = Repo.get!(Application, application_id)

    cond do
      test_env?() ->
        Logger.debug("WebhookNotifier: test env, skipping real HTTP",
          application_id: app.id,
          status: app.status,
          risk_score: app.risk_score
        )

        :ok

      skip_webhooks?() ->
        Logger.debug("WebhookNotifier: skipping webhook (skip_webhooks=true)",
          application_id: app.id,
          status: app.status,
          risk_score: app.risk_score
        )

        :ok

      true ->
        do_send_webhook(app)
    end
  end

  defp test_env? do
    # Works in mix environments; safe even in releases if MIX_ENV not present.
    System.get_env("MIX_ENV") == "test"
  end

  defp skip_webhooks? do
    # Config app-level (mantiene compatibilidad con tu código actual)
    Elixir.Application.get_env(:bravo_multipais, :skip_webhooks, false) ||
      System.get_env("SKIP_WEBHOOKS") in ["true", "1", "TRUE"]
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

  defp do_send_webhook(%Application{} = app) do
    url = webhook_url()

    payload = %{
      event_id: Ecto.UUID.generate(),
      event_type: @event_type,
      version: @event_version,
      data: %{
        application_id: app.id,
        status: app.status,
        risk_score: app.risk_score,
        country: app.country
      }
    }

    body = Jason.encode!(payload)

    headers = [
      {"content-type", "application/json"},
      {"x-bravo-event", @event_type},
      {"x-bravo-event-version", @event_version}
    ]

    Logger.info("WebhookNotifier: sending webhook",
      application_id: app.id,
      status: app.status,
      url: url
    )

    Finch.build(:post, url, headers, body)
    |> Finch.request(BravoMultipais.Finch)
    |> handle_http_response(app)
  end

  defp handle_http_response({:ok, resp}, %Application{} = app) do
    case resp.status do
      status when status in 200..299 ->
        Logger.info("WebhookNotifier: delivered",
          application_id: app.id,
          status: app.status,
          http_status: status
        )

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

      status when status in 400..499 ->
        Logger.error("WebhookNotifier: permanent failure (4xx), discarding",
          application_id: app.id,
          http_status: status,
          response: inspect(resp)
        )

        :discard

      status ->
        Logger.error("WebhookNotifier: transient failure (5xx), will retry",
          application_id: app.id,
          http_status: status,
          response: inspect(resp)
        )

        {:error, {:http_error, status}}
    end
  end

  defp handle_http_response({:error, reason}, %Application{} = app) do
    Logger.error("WebhookNotifier: network/finch error, will retry",
      application_id: app.id,
      reason: inspect(reason)
    )

    {:error, reason}
  end

  defp webhook_url do
    Elixir.Application.get_env(
      :bravo_multipais,
      :webhook_url,
      "http://localhost:4001/webhooks/applications"
    )
  end
end
