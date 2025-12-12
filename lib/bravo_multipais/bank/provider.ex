defmodule BravoMultipais.Bank.Provider do
  @moduledoc """
  Contrato común para proveedores bancarios por país.

  En un entorno real, aquí hablarías con APIs externas distintas.
  Para esta prueba, devolvemos datos simulados pero consistentes
  con el perfil financiero que necesita el dominio.
  """

  @type document :: map()
  @type raw_bank_data :: map()

  @callback fetch_info(document()) :: {:ok, raw_bank_data()} | {:error, term()}
end
