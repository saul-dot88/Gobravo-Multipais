defmodule BravoMultipais.Policies.Policy do
  @moduledoc """
  Contrato común para políticas de negocio por país.

  Cada país implementa:
    * validación del documento de identidad
    * reglas de negocio básicas (relación monto / ingreso / deuda)
    * estado inicial de la solicitud al crearse
    * evaluación de riesgo (score + estado final)
  """

  @type document :: map()
  @type app_params :: %{
          country: String.t(),
          full_name: String.t(),
          document: map(),
          amount: Decimal.t() | number(),
          monthly_income: Decimal.t() | number(),
          bank_profile: map()
        }

  @callback validate_document(document()) :: :ok | {:error, term()}
  @callback business_rules(app_params(), map()) :: :ok | {:error, term()}
  @callback next_status_on_creation(app_params(), map()) :: String.t()

  @doc """
  Evalúa el riesgo de una solicitud ya creada usando su perfil bancario.

  Debe regresar:
    * score: entero, típicamente entre 300 y 850
    * final_status: "APPROVED" | "REJECTED" | "UNDER_REVIEW"
  """
  @callback assess_risk(app_params(), map()) :: %{score: integer(), final_status: String.t()}
end
