defmodule BravoMultipais.Jobs.EvaluateRisk do
  @moduledoc """
  Job que evalúa el riesgo de una solicitud de crédito.

  Lee la solicitud de la base de datos, aplica la política del país,
  calcula un risk_score y actualiza el estado a:
    - APPROVED
    - REJECTED
    - UNDER_REVIEW

  Luego emite un broadcast para que el LiveView/Frontend
  actualice la UI en tiempo (casi) real.
  """

  use Oban.Worker, queue: :risk, max_attempts: 5

  alias BravoMultipais.CreditApplications.Application
  alias BravoMultipais.Policies.Factory, as: PolicyFactory
  alias BravoMultipais.Repo
  alias BravoMultipaisWeb.Endpoint
  import Ecto.Changeset

  @final_statuses ~w(APPROVED REJECTED)

  @impl true
  def perform(%Oban.Job{args: %{"application_id" => id}}) do
    case Repo.get(Application, id) do
      nil ->
        # La solicitud ya no existe, no vale la pena reintentar
        :discard

      %Application{status: status} when status in @final_statuses ->
        # Ya fue evaluada antes: idempotencia
        :ok

      %Application{} = app ->
        do_evaluate(app)
    end
  end

  defp do_evaluate(%Application{} = app) do
    policy = PolicyFactory.policy_for(app.country)
    bank_profile = app.bank_profile || %{}

    app_params = %{
      country: app.country,
      full_name: app.full_name,
      document: app.document,
      amount: app.amount,
      monthly_income: app.monthly_income,
      bank_profile: bank_profile
    }

    %{score: score, final_status: final_status} =
      policy.assess_risk(app_params, bank_profile)

    changeset =
      app
      |> Application.status_changeset(final_status)
      |> change(risk_score: score)

    case Repo.update(changeset) do
      {:ok, updated} ->
        # Aquí avisamos al LiveView de que cambió el estado
        Endpoint.broadcast(
          "applications",
          "status_changed",
          %{
            id: updated.id,
            country: updated.country,
            status: updated.status,
            risk_score: updated.risk_score
          }
        )

        :ok

      {:error, _changeset} ->
        {:error, :update_failed}
    end
  end
end
