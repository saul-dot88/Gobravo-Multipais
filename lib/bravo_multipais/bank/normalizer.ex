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

  @doc """
  Construye un mapa de documento normalizado por país a partir de un único valor
  capturado en el formulario.

  Esto permite que las Policies trabajen con un shape consistente de `document`.
  """
  @spec build_document_map(String.t(), String.t() | nil) :: map()
  def build_document_map(country, value)

  # España: usamos `dni` como key por defecto (podrías refinar a NIF/NIE si quisieras)
  def build_document_map("ES", value) do
    %{
      "dni" => value
    }
  end

  # Italia: usamos `codice_fiscale`
  def build_document_map("IT", value) do
    %{
      "codice_fiscale" => value
    }
  end

  # Portugal: usamos `nif`
  def build_document_map("PT", value) do
    %{
      "nif" => value
    }
  end

  # Fallback para otros países (por si en un futuro agregas más)
  def build_document_map(country, value) do
    %{
      "country" => country,
      "raw" => value
    }
  end

end
