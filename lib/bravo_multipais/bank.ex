defmodule BravoMultipais.Bank do
  @moduledoc """
  Capa simplificada de integración bancaria.

  Para el MVP, `fetch_profile/2` devuelve un perfil bancario simulado,
  consistente en estructura, a partir de los datos de la solicitud.
  """

  @type profile :: %{
          country: String.t(),
          external_id: String.t(),
          total_debt: number(),
          avg_balance: number(),
          currency: String.t(),
          score: integer()
        }

  @spec fetch_profile(String.t(), map()) :: {:ok, profile()}
  def fetch_profile(country, app_attrs) when is_binary(country) and is_map(app_attrs) do
    {:ok, build_mock_profile(country, app_attrs)}
  end

  # ----------------------
  # Internals
  # ----------------------

  defp build_mock_profile(country, app_attrs) do
    amount = to_float(app_attrs[:amount] || app_attrs["amount"])
    income = to_float(app_attrs[:monthly_income] || app_attrs["monthly_income"])
    doc    = app_attrs[:document] || app_attrs["document"] || %{}

    base_currency =
      case country do
        "ES" -> "EUR"
        "IT" -> "EUR"
        "PT" -> "EUR"
        _ -> "EUR"
      end

    # Intento simple de tener algo “realista”
    total_debt =
      if income > 0 do
        min(income * 0.6, amount * 0.8)
      else
        0.0
      end

    avg_balance =
      if income > 0 do
        income * 0.4
      else
        0.0
      end

    # Armar external_id a partir del documento si existe
    raw_doc =
      doc["dni"] ||
        doc["codice_fiscale"] ||
        doc["nif"] ||
        doc["raw"] ||
        "GENERIC"

    external_id = "BANK-" <> to_string(raw_doc)

    # Un score base fijo, podrías hacerlo más sofisticado si quieres
    score = 700

    %{
      country: country,
      external_id: external_id,
      total_debt: total_debt,
      avg_balance: avg_balance,
      currency: base_currency,
      score: score
    }
  end

  # Helpers numéricos básicos

  defp to_float(nil), do: 0.0

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)

  defp to_float(n) when is_integer(n) or is_float(n), do: n * 1.0

  defp to_float(s) when is_binary(s) do
    case Float.parse(s) do
      {v, _} -> v
      :error -> 0.0
    end
  end

  defp to_float(_), do: 0.0
end
