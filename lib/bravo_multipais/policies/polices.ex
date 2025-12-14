defmodule BravoMultipais.Policies do
  @moduledoc """
  Punto de entrada para seleccionar la política de riesgo según país.
  """

  @type country :: String.t()
  @type policy_module :: module()

  @spec policy_for(country) :: policy_module
  def policy_for(country) do
    case country |> to_string() |> String.upcase() do
      "ES" ->
        BravoMultipais.Policies.ES

      "IT" ->
        BravoMultipais.Policies.IT

      "PT" ->
        BravoMultipais.Policies.PT

      other ->
        raise "No policy defined for country #{inspect(other)}"
    end
  end
end
