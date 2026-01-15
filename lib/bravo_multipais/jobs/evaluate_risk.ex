defmodule BravoMultipais.Jobs.EvaluateRisk do
  @moduledoc """
  Job de dominio que evalúa el riesgo de una solicitud de crédito.

  NO sabe nada de Oban, ni de PubSub ni de la base de datos.
  Solo recibe una `Application` y devuelve score + final_status.
  """

  alias BravoMultipais.CreditApplications.Application
  alias BravoMultipais.Policies

  @type result :: %{
          score: integer(),
          final_status: String.t()
        }

  @spec run(Application.t()) :: result
  def run(%Application{} = app) do
    policy = Policies.policy_for(app.country)
    bank_profile = app.bank_profile || %{}

    params = %{
      country: app.country,
      full_name: app.full_name,
      document: app.document,
      amount: app.amount,
      monthly_income: app.monthly_income,
      bank_profile: bank_profile
    }

    policy.assess_risk(params, bank_profile)
  end
end
