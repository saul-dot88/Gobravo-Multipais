defmodule BravoMultipais.Policies.Policy do
  @moduledoc """
  Behaviour común para todas las políticas de evaluación de riesgo por país.
  """

  @type attrs :: map()
  @type document :: map()
  @type bank_profile :: map()
  @type risk_result :: %{score: integer(), final_status: String.t()}
  @type error_reason :: term()

  @callback validate_document(document()) :: :ok | {:error, error_reason()}
  @callback business_rules(attrs(), bank_profile()) :: :ok | {:error, error_reason()}
  @callback next_status_on_creation(attrs(), bank_profile()) :: String.t()
  @callback assess_risk(attrs(), bank_profile()) :: risk_result()
end
