defmodule BravoMultipais.Bank.Normalizer do
  @moduledoc """
  Normaliza las respuestas crudas de los proveedores bancarios
  (que son distintas por país) a un perfil interno homogéneo.
  """

  @type raw :: map()
  @type profile :: %{
          external_id: String.t(),
          total_debt: number(),
          avg_balance: number() | nil,
          score: integer() | nil,
          currency: String.t(),
          raw: map()
        }

  @spec normalize(String.t(), raw()) :: profile()
  def normalize("ES", raw) when is_map(raw) do
    %{
      external_id: Map.get(raw, "iban", "ES-UNKNOWN"),
      total_debt: to_float(Map.get(raw, "total_debt", 0)),
      avg_balance: to_float(Map.get(raw, "avg_balance", 0)),
      score: Map.get(raw, "score") || Map.get(raw, "credit_score"),
      currency: Map.get(raw, "currency", "EUR"),
      raw: raw
    }
  end

  def normalize("IT", raw) when is_map(raw) do
    %{
      external_id: Map.get(raw, "iban", "IT-UNKNOWN"),
      total_debt: to_float(Map.get(raw, "total_debt", 0)),
      avg_balance: to_float(Map.get(raw, "avg_balance", 0)),
      score: Map.get(raw, "credit_score"),
      currency: Map.get(raw, "currency", "EUR"),
      raw: raw
    }
  end

  def normalize("PT", raw) when is_map(raw) do
    %{
      external_id: Map.get(raw, "iban", "PT-UNKNOWN"),
      total_debt: to_float(Map.get(raw, "total_debt", 0)),
      avg_balance: to_float(Map.get(raw, "avg_balance", 0)),
      score: Map.get(raw, "credit_score"),
      currency: Map.get(raw, "currency", "EUR"),
      raw: raw
    }
  end

  def normalize(country, raw) when is_binary(country) do
    # Fallback genérico por si se agregan países nuevos y se olvidó implementar
    %{
      external_id: Map.get(raw, "iban", "UNKNOWN"),
      total_debt: to_float(Map.get(raw, "total_debt", 0)),
      avg_balance: to_float(Map.get(raw, "avg_balance", 0)),
      score: Map.get(raw, "credit_score") || Map.get(raw, "score"),
      currency: Map.get(raw, "currency", "EUR"),
      raw: raw
    }
  end

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_number(n), do: n * 1.0
  defp to_float(_), do: 0.0
end
