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

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"application_id" => app_id}}) do
    # 1) Buscar la solicitud
    case Repo.get(Application, app_id) do
      nil ->
        # Si ya no existe, descartamos el job (no tiene sentido reintentar)
        {:discard, :application_not_found}

      %Application{} = app ->
        do_evaluate(app)
    end
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
