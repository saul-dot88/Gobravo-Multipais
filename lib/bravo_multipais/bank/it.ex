defmodule BravoMultipais.Bank.IT do
  @behaviour BravoMultipais.Bank.Provider

  @moduledoc """
  Proveedor bancario simulado para Italia.

  Dado un codice fiscale, devolvemos una foto simplificada del perfil
  financiero: deuda total, saldo promedio y un score aproximado.
  """

  @impl true
  def fetch_info(document) when is_map(document) do
    cf =
      Map.get(document, "codice_fiscale") ||
        Map.get(document, :codice_fiscale, "")

    seed = :erlang.phash2(cf, 10)

    base_total_debt = 6_000 + seed * 600
    base_avg_balance = 2_500 + seed * 150
    base_score = 650 + rem(seed * 23, 80)

    {:ok,
     %{
       "iban" => "IT60-#{seed}-SIMULATED-IBAN",
       "total_debt" => base_total_debt,
       "avg_balance" => base_avg_balance,
       "credit_score" => base_score,
       "currency" => "EUR"
     }}
  end

  def fetch_info(_), do: {:error, :invalid_document_format}
end
