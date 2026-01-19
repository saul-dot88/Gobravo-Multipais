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

  alias BravoMultipais.CreditApplications.{Application, Events, EventTypes}
  alias BravoMultipais.Repo
  alias BravoMultipaisWeb.Endpoint

  require Logger

  @topic "applications"
  @event_type "application.status_changed"
  @event_version "v1"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"application_id" => id} = args}) do
    app = Repo.get!(Application, id)

    status = Map.get(args, "status", app.status)
    source = Map.get(args, "source", "auto")

    cond do
      test_env?() ->
        _ =
          Events.record(
            app.id,
            EventTypes.webhook_skipped(),
            %{
              reason: "test_env",
              source: source
            }, source: "webhook_worker")

        :ok

      skip_webhooks?() ->
        _ =
          Events.record(
            app.id,
            EventTypes.webhook_skipped(),
            %{
              reason: "skip_webhooks",
              source: source
            }, source: "webhook_worker")

        :ok

      true ->
        do_send_webhook(app, status, source)
    end
  end

  @doc """
  Helper para encolar el job del webhook desde cualquier parte del dominio.
  """
  @spec enqueue(Ecto.UUID.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def enqueue(application_id, status, opts \\ [])
      when is_binary(application_id) and is_binary(status) do
    source = Keyword.get(opts, :source, "auto")

    %{
      "application_id" => application_id,
      "status" => status,
      "source" => source
    }
    |> __MODULE__.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def enqueue_manual(application_id, status)
      when is_binary(application_id) and is_binary(status) do
    enqueue(application_id, status, source: "manual")
  end

  # --- implementación real para dev/prod ---

  defp do_send_webhook(%Application{} = app, status, source) do
    url = webhook_url()

    payload = %{
      event_id: Ecto.UUID.generate(),
      event_type: @event_type,
      version: @event_version,
      data: %{
        application_id: app.id,
        status: status,
        risk_score: app.risk_score,
        country: app.country,
        source: source
      }
    }

    body = Jason.encode!(payload)

    headers = [
      {"content-type", "application/json"},
      {"x-bravo-event", @event_type},
      {"x-bravo-event-version", @event_version},
      {"x-bravo-source", source}
    ]

    _ =
      Events.record(
        app.id,
        EventTypes.webhook_sending(),
        %{
          url: url,
          status: status,
          risk_score: app.risk_score,
          source: source
        }, source: "webhook_worker")

    Finch.build(:post, url, headers, body)
    |> Finch.request(BravoMultipais.Finch)
    |> handle_http_response(app, url, source)
  end

  defp handle_http_response({:ok, resp}, %Application{} = app, url, source) do
    case resp.status do
      status when status in 200..299 ->
        _ =
          Events.record(
            app.id,
            EventTypes.webhook_sent(),
            %{
              url: url,
              http_status: status,
              source: source
            }, source: "webhook_worker")

        Endpoint.broadcast(@topic, "webhook_resent", %{
          application_id: app.id,
          at: DateTime.utc_now()
        })

        :ok

      status when status in 400..499 ->
        _ =
          Events.record(
            app.id,
            EventTypes.webhook_discarded(),
            %{
              url: url,
              http_status: status,
              source: source
            }, source: "webhook_worker")

        :discard

      status ->
        _ =
          Events.record(
            app.id,
            EventTypes.webhook_failed(),
            %{
              url: url,
              http_status: status,
              source: source
            }, source: "webhook_worker")

        {:error, {:http_error, status}}
    end
  end

  defp handle_http_response({:error, reason}, %Application{} = app, url, source) do
    _ =
      Events.record(
        app.id,
        EventTypes.webhook_failed(),
        %{
          url: url,
          reason: inspect(reason),
          source: source
        }, source: "webhook_worker")

    {:error, reason}
  end

  defp test_env? do
    System.get_env("MIX_ENV") == "test"
  end

  defp skip_webhooks? do
    Elixir.Application.get_env(:bravo_multipais, :skip_webhooks, false) ||
      System.get_env("SKIP_WEBHOOKS") in ["true", "1", "TRUE"]
  end

  defp webhook_url do
    Elixir.Application.get_env(
      :bravo_multipais,
      :webhook_url,
      "http://localhost:4001/webhooks/applications"
    )
  end
end
