defmodule BravoMultipais.Bank.ES do
  @behaviour BravoMultipais.Bank.Provider

  @moduledoc """
  Proveedor bancario simulado para España.

  En un entorno real, aquí se llamaría a un API externo que, dado un DNI/NIF/NIE,
  devuelve la foto financiera del cliente. Para la prueba devolvemos datos
  determinísticos y sencillos.
  """

  @impl true
  def fetch_info(document) when is_map(document) do
    # Tomamos algún valor del documento para "personalizar" un poco.
    # No es necesario algo sofisticado; basta con tener algo reproducible.
    seed =
      document
      |> Map.values()
      |> Enum.join()
      |> :erlang.phash2(10)

    base_total_debt = 8_000 + seed * 500
    base_avg_balance = 2_000 + seed * 200

    {:ok,
     %{
       "iban" => "ES00-#{seed}-SIMULATED-IBAN",
       "total_debt" => base_total_debt,
       "avg_balance" => base_avg_balance,
       "currency" => "EUR"
     }}
  end

  def fetch_info(_), do: {:error, :invalid_document_format}
end
