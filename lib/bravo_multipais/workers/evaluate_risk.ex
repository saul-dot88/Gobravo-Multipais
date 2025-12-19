defmodule BravoMultipais.Workers.EvaluateRisk do
  @moduledoc """
  Worker de Oban que toma una solicitud de crédito,
  ejecuta la lógica de scoring y actualiza su estado final.
  """

  use Oban.Worker,
    queue: :risk,
    max_attempts: 5,
    unique: [fields: [:args, :queue], period: 60]

  alias BravoMultipais.Repo
  alias BravoMultipais.CreditApplications.Application
  alias BravoMultipais.Policies
  alias BravoMultipais.Bank
  alias BravoMultipaisWeb.Endpoint
   alias BravoMultipais.Workers.WebhookNotifier

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"application_id" => id}}) do
    app = Repo.get!(Application, id)

    policy = Policies.policy_for(app.country)
    bank_profile = Bank.fetch_profile!(app.country, app)

    %{score: score, final_status: final_status} =
      policy.assess_risk(app, bank_profile)

    {:ok, app} =
      app
      |> Application.changeset(%{
        risk_score: score,
        status: final_status,
        bank_profile: bank_profile
      })
      |> Repo.update()

    Logger.info("Risk evaluation completed",
      application_id: app.id,
      status: app.status,
      risk_score: app.risk_score
    )

    # 1) Notificar al frontend (ya lo tenías):
    Phoenix.PubSub.broadcast(
      BravoMultipais.PubSub,
      "applications",
      %Phoenix.Socket.Broadcast{
        topic: "applications",
        event: "updated",
        payload: %{id: app.id}
      }
    )

    # 2) Encolar webhook externo
    :ok = WebhookNotifier.enqueue(app.id)

    :ok
  end

  def perform(%Oban.Job{args: args}) do
    # Cualquier payload raro lo descartamos explícitamente
    {:discard, {:invalid_args, args}}
  end

  # ======================
  # Lógica interna
  # ======================

  defp do_evaluate(%Application{} = app) do
    # Usamos el perfil bancario guardado en la creación.
    bank_profile = app.bank_profile || %{}

    policy = Policies.policy_for(app.country)

    # Calculamos score y estado final
    %{score: score, final_status: final_status} =
      policy.assess_risk(app, bank_profile)

    # Actualizamos la solicitud
    changeset =
      app
      |> Application.changeset(%{
        status: final_status,
        risk_score: score,
        bank_profile: bank_profile
      })

    case Repo.update(changeset) do
      {:ok, updated} ->
        # Avisamos al LiveView (si está suscrito) para refrescar la tabla en tiempo real
        Endpoint.broadcast("applications", "updated", %{id: updated.id})
        :ok

      {:error, changeset} ->
        {:error, {:update_failed, changeset}}
    end
  end
end
