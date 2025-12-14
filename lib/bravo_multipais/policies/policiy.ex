defmodule BravoMultipais.Policies.Policy do
  @moduledoc """
  Behaviour para políticas de riesgo por país.

  Cada módulo de país (ES/IT/PT) debe implementar:
  - validate_document/1
  - business_rules/2
  - next_status_on_creation/2
  - assess_risk/2
  """

  @callback validate_document(map()) :: :ok | {:error, term()}

  @callback business_rules(app :: map() | struct(), bank_profile :: map()) ::
              :ok | {:error, term()}

  @callback next_status_on_creation(app :: map() | struct(), bank_profile :: map()) ::
              String.t()

  @callback assess_risk(app :: map() | struct(), bank_profile :: map()) ::
              %{score: integer(), final_status: String.t()}
end
