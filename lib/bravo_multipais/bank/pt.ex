defmodule BravoMultipais.Bank.PT do
  @behaviour BravoMultipais.Bank.Provider

  @moduledoc """
  Proveedor bancario simulado para Portugal.

  Dado un NIF, devolvemos información de deuda, saldo promedio y un score simple.
  """

  @impl true
  def fetch_info(document) when is_map(document) do
    nif = Map.get(document, "nif") || Map.get(document, :nif, "")
    seed = :erlang.phash2(nif, 10)

    base_total_debt = 5_000 + seed * 400
    base_avg_balance = 1_800 + seed * 180
    base_score = 630 + rem(seed * 17, 70)

    {:ok,
     %{
       "iban" => "PT50-#{seed}-SIMULATED-IBAN",
       "total_debt" => base_total_debt,
       "avg_balance" => base_avg_balance,
       "credit_score" => base_score,
       "currency" => "EUR"
     }}
  end

  def fetch_info(_), do: {:error, :invalid_document_format}
end
