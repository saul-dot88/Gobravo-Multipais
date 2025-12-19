defmodule BravoMultipais.Bank do
  @moduledoc """
  Capa de integración con el "proveedor bancario" (simulado).

  Por ahora sólo generamos un perfil mock a partir de los datos
  de la solicitud.
  """

  alias BravoMultipais.CreditApplications.Application

  @type profile :: %{
          country: String.t(),
          external_id: String.t(),
          total_debt: number(),
          avg_balance: number(),
          score: integer(),
          currency: String.t()
        }

  @spec fetch_profile(String.t(), map() | Application.t()) :: {:ok, profile()}
  def fetch_profile(country, app_or_attrs)
      when is_binary(country) and is_map(app_or_attrs) do
    {:ok, build_mock_profile(country, app_or_attrs)}
  end

  # Versión bang, para el worker EvaluateRisk
  @spec fetch_profile!(String.t(), map() | Application.t()) :: profile()
  def fetch_profile!(country, app_or_attrs) do
    case fetch_profile(country, app_or_attrs) do
      {:ok, profile} ->
        profile

      {:error, reason} ->
        raise "Error fetching bank profile: #{inspect(reason)}"
    end
  end

  # =========================
  # Helpers internos
  # =========================

  # Normalizamos attrs para que siempre trabajemos con un map "simple"
  defp normalize_attrs(%Application{} = app) do
    %{
      "country" => app.country,
      "full_name" => app.full_name,
      "document" => app.document,
      "amount" => app.amount,
      "monthly_income" => app.monthly_income
    }
  end

  defp normalize_attrs(attrs) when is_map(attrs), do: attrs

  defp build_mock_profile(country, app_or_attrs) do
    attrs = normalize_attrs(app_or_attrs)

    amount =
      attrs
      |> get_field(["amount"])
      |> decimal_to_float()

    monthly_income =
      attrs
      |> get_field(["monthly_income"])
      |> decimal_to_float()

    doc = get_field(attrs, ["document"]) || %{}

    raw_doc =
      doc["dni"] ||
        doc[:dni] ||
        doc["codice_fiscale"] ||
        doc[:codice_fiscale] ||
        doc["nif"] ||
        doc[:nif] ||
        doc["raw"] ||
        doc[:raw] ||
        "UNKNOWN"

    %{
      country: country,
      external_id: "BANK-#{raw_doc}",
      total_debt: Float.round(monthly_income * 0.6, 2),
      avg_balance: Float.round(monthly_income * 0.4, 2),
      score: 700,
      currency: "EUR"
    }
  end

  # Lee un campo aceptando tanto string como atom
  defp get_field(map, [key]) do
    Map.get(map, key) || Map.get(map, to_string(key)) || Map.get(map, String.to_atom("#{key}"))
  rescue
    ArgumentError ->
      Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp decimal_to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp decimal_to_float(n) when is_number(n), do: n * 1.0
  defp decimal_to_float(nil), do: 0.0

  defp decimal_to_float(n) when is_binary(n) do
    n
    |> String.trim()
    |> case do
      "" ->
        0.0

      value ->
        case Decimal.new(value) do
          %Decimal{} = d -> Decimal.to_float(d)
        end
    end
  rescue
    _ ->
      0.0
  end
end
