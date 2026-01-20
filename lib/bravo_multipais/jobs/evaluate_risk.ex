defmodule BravoMultipais.Jobs.EvaluateRisk do
  @moduledoc """
  Job de dominio que evalúa el riesgo de una solicitud de crédito.

  NO sabe nada de Oban, ni de PubSub ni de la base de datos.
  Solo recibe una `Application` y devuelve score + final_status.

  Soporta policy versioning de forma opcional vía opts:
    - :policy_version (ej "v1")
    - :policy (module) (override explícito)
  """

  alias BravoMultipais.CreditApplications.Application
  alias BravoMultipais.Policies

  @type result :: %{
          score: integer(),
          final_status: String.t()
        }

  @spec run(Application.t(), keyword()) :: result
  def run(%Application{} = app, opts \\ []) do
    bank_profile = app.bank_profile || %{}

    policy_version = Keyword.get(opts, :policy_version)
    policy_override = Keyword.get(opts, :policy)

    policy =
      cond do
        is_atom(policy_override) ->
          policy_override

        is_binary(policy_version) ->
          Policies.policy_for(app.country, policy_version)

        true ->
          Policies.policy_for(app.country)
      end

    params = %{
      country: app.country,
      full_name: app.full_name,
      document: app.document,
      amount: app.amount,
      monthly_income: app.monthly_income
    }

    # La policy ya soporta leer de map/struct.
    policy.assess_risk(params, bank_profile)
  end
end
