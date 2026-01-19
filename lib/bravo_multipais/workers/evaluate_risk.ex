defmodule BravoMultipais.Workers.EvaluateRisk do
  @moduledoc """
  Worker Oban que ejecuta el job de dominio `BravoMultipais.Jobs.EvaluateRisk`.

  Responsabilidades:
    * Leer la aplicación desde la base de datos.
    * Ejecutar el job de dominio.
    * Actualizar la aplicación (status + risk_score).
    * Notificar al LiveView via PubSub.
    * Encolar webhook notifier (si está habilitado).
  """

  use Oban.Worker,
    queue: :risk,
    max_attempts: 5,
    unique: [
      fields: [:worker, :queue, :args],
      keys: [:application_id],
      period: 60,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias BravoMultipais.CreditApplications.Application
  alias BravoMultipais.Jobs.EvaluateRisk, as: EvaluateRiskJob
  alias BravoMultipais.LogSanitizer
  alias BravoMultipais.Repo
  alias BravoMultipais.Workers.WebhookNotifier
  alias BravoMultipaisWeb.Endpoint
  alias BravoMultipais.CreditApplications.{Events, EventTypes}

  import Ecto.Changeset, only: [change: 2]
  require Logger

  @topic "applications"
  @final_statuses ~w(APPROVED REJECTED UNDER_REVIEW)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"application_id" => id}}) do
    Logger.info("Risk worker: perform/1 called", application_id: id)

    case Repo.get(Application, id) do
      nil ->
        Logger.warning("Risk worker: application not found", application_id: id)
        :discard

      %Application{status: status} = app when status in @final_statuses ->
        Logger.info("Risk worker: already in final status",
          application_id: app.id,
          status: app.status
        )

        :ok

      %Application{} = app ->
        Logger.info("Risk worker: evaluating risk",
          application_id: app.id,
          current_status: app.status,
          current_score: app.risk_score
        )

        %{score: score, final_status: final_status} = EvaluateRiskJob.run(app)

        changeset =
          app
          |> Application.status_changeset(final_status)
          |> change(risk_score: score)

        case Repo.update(changeset) do
          {:ok, updated} ->
            Logger.info("Risk worker: update OK",
              application_id: updated.id,
              new_status: updated.status,
              new_score: updated.risk_score,
              document_masked: LogSanitizer.mask_document(updated.document)
            )

            # Audit: risk evaluated (REAL)
            _ =
              Events.record(
                updated.id,
                "risk_evaluated",
                %{
                  country: updated.country,
                  status: updated.status,
                  risk_score: updated.risk_score
                }, source: "risk_worker")

            Endpoint.broadcast(@topic, "status_changed", %{
              id: updated.id,
              country: updated.country,
              status: updated.status,
              risk_score: updated.risk_score
            })

            maybe_enqueue_webhook(updated)

            :ok

          {:error, changeset} ->
            Logger.error("Risk worker: update FAILED",
              application_id: app.id,
              errors: changeset.errors
            )

            {:error, :update_failed}
        end
    end
  end

  defp maybe_enqueue_webhook(%Application{} = app) do
    source = "auto"

    case WebhookNotifier.enqueue(app.id, app.status, source: source) do
      :ok ->
        _ =
          Events.record(
            app.id,
            EventTypes.webhook_enqueued(),
            %{
              status: app.status,
              source: source
            }, source: "risk_worker")

        :ok

      {:error, reason} ->
        _ =
          Events.record(
            app.id,
            EventTypes.webhook_enqueue_failed(),
            %{
              status: app.status,
              source: source,
              reason: inspect(reason)
            }, source: "risk_worker")

        :ok
    end
  end

  @doc """
  API de conveniencia para encolar un job de riesgo desde Commands/dominio.
  """
  @spec enqueue(Ecto.UUID.t()) :: :ok | {:error, term()}
  def enqueue(application_id) when is_binary(application_id) do
    %{"application_id" => application_id}
    |> new()
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
