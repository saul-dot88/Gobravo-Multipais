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
      # Importante: dedupe por application+status+source para no “comerte”
      # transiciones rápidas (p.ej. UNDER_REVIEW -> APPROVED en < 60s).
      keys: [:application_id, :status, :source],
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
  def perform(
        %Oban.Job{id: job_id, attempt: attempt, args: %{"application_id" => id} = args} = job
      ) do
    case Repo.get(Application, id) do
      nil ->
        Logger.warning("WebhookNotifier: application not found, discarding",
          application_id: id,
          oban_job_id: job_id,
          attempt: attempt
        )

        :discard

      %Application{} = app ->
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
                  status: status,
                  source: source,
                  oban_job_id: job_id,
                  attempt: attempt
                },
                source: "webhook_worker"
              )

            :ok

          skip_webhooks?() ->
            _ =
              Events.record(
                app.id,
                EventTypes.webhook_skipped(),
                %{
                  reason: "skip_webhooks",
                  status: status,
                  source: source,
                  oban_job_id: job_id,
                  attempt: attempt
                },
                source: "webhook_worker"
              )

            :ok

          true ->
            do_send_webhook(app, status, source, job)
        end
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

  defp do_send_webhook(%Application{} = app, status, source, %Oban.Job{
         id: job_id,
         attempt: attempt
       }) do
    url = webhook_url()
    event_id = Ecto.UUID.generate()
    started_at = System.monotonic_time()

    payload = %{
      event_id: event_id,
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
      {"x-bravo-source", source},
      {"x-bravo-event-id", event_id}
    ]

    Logger.info("WebhookNotifier: sending webhook",
      application_id: app.id,
      status: status,
      url: url,
      event_id: event_id,
      oban_job_id: job_id,
      attempt: attempt
    )

    _ =
      Events.record(
        app.id,
        EventTypes.webhook_sending(),
        %{
          url: url,
          status: status,
          risk_score: app.risk_score,
          source: source,
          event_id: event_id,
          oban_job_id: job_id,
          attempt: attempt
        },
        source: "webhook_worker"
      )

    Finch.build(:post, url, headers, body)
    |> Finch.request(BravoMultipais.Finch)
    |> handle_http_response(app, url, source, event_id, job_id, attempt, started_at)
  end

  defp handle_http_response(
         {:ok, resp},
         %Application{} = app,
         url,
         source,
         event_id,
         job_id,
         attempt,
         started_at
       ) do
    duration_ms = duration_ms_since(started_at)

    case resp.status do
      http_status when http_status in 200..299 ->
        _ =
          Events.record(
            app.id,
            EventTypes.webhook_sent(),
            %{
              url: url,
              http_status: http_status,
              source: source,
              event_id: event_id,
              oban_job_id: job_id,
              attempt: attempt,
              duration_ms: duration_ms
            },
            source: "webhook_worker"
          )

        Endpoint.broadcast(@topic, "webhook_resent", %{
          application_id: app.id,
          at: DateTime.utc_now()
        })

        :ok

      http_status when http_status in 400..499 ->
        _ =
          Events.record(
            app.id,
            EventTypes.webhook_discarded(),
            %{
              url: url,
              http_status: http_status,
              source: source,
              event_id: event_id,
              oban_job_id: job_id,
              attempt: attempt,
              duration_ms: duration_ms,
              response_body: truncate_body(resp.body)
            },
            source: "webhook_worker"
          )

        :discard

      http_status ->
        _ =
          Events.record(
            app.id,
            EventTypes.webhook_failed(),
            %{
              url: url,
              http_status: http_status,
              source: source,
              event_id: event_id,
              oban_job_id: job_id,
              attempt: attempt,
              duration_ms: duration_ms,
              response_body: truncate_body(resp.body)
            },
            source: "webhook_worker"
          )

        {:error, {:http_error, http_status}}
    end
  end

  defp handle_http_response(
         {:error, reason},
         %Application{} = app,
         url,
         source,
         event_id,
         job_id,
         attempt,
         started_at
       ) do
    duration_ms = duration_ms_since(started_at)

    _ =
      Events.record(
        app.id,
        EventTypes.webhook_failed(),
        %{
          url: url,
          reason: inspect(reason),
          source: source,
          event_id: event_id,
          oban_job_id: job_id,
          attempt: attempt,
          duration_ms: duration_ms
        },
        source: "webhook_worker"
      )

    {:error, reason}
  end

  defp duration_ms_since(started_at_native) do
    System.monotonic_time()
    |> Kernel.-(started_at_native)
    |> System.convert_time_unit(:native, :millisecond)
  end

  defp truncate_body(nil), do: nil
  defp truncate_body(body) when is_binary(body), do: String.slice(body, 0, 500)
  defp truncate_body(other), do: inspect(other) |> String.slice(0, 500)

  defp test_env? do
    Code.ensure_loaded?(Mix) and Mix.env() == :test
  end

  defp skip_webhooks? do
    Application.get_env(:bravo_multipais, :skip_webhooks, false) ||
      System.get_env("SKIP_WEBHOOKS") in ["true", "1", "TRUE"]
  end

  defp webhook_url do
    Application.get_env(
      :bravo_multipais,
      :webhook_url,
      "http://localhost:4001/webhooks/applications"
    )
  end
end
