defmodule BravoMultipais.Policies.IT do
  @moduledoc """
  Políticas de validación y riesgo para Italia.
  """

  @behaviour BravoMultipais.Policies.Policy

  ## Callbacks

  @impl true
  def validate_document(doc) when is_map(doc) do
    cf =
      doc
      |> get("codice_fiscale")
      |> to_string()
      |> String.trim()

    cond do
      cf == "" ->
        {:error, :missing_document}

      looks_like_spanish_dni?(cf) ->
        # Eligieron IT pero metieron algo que parece DNI ES
        {:error, {:document_country_mismatch, expected: "IT", detected: "ES"}}

      String.length(cf) < 11 ->
        {:error, :invalid_codice_fiscale}

      true ->
        :ok
    end
  end

  @impl true
  def business_rules(app, bank_profile) do
    amount = to_float(get(app, "amount") || Map.get(app, :amount))
    income = to_float(get(app, "monthly_income") || Map.get(app, :monthly_income))
    total_debt = to_float(Map.get(bank_profile, :total_debt, 0))

    cond do
      income <= 0 ->
        {:error, :invalid_income}

      amount > income * 15 ->
        {:error, :amount_too_high_relative_to_income}

      safe_ratio(total_debt, income) > 6 ->
        {:error, :debt_to_income_too_high}

      true ->
        :ok
    end
  end

  @impl true
  def next_status_on_creation(app, _bank_profile) do
    amount = to_float(get(app, "amount") || Map.get(app, :amount))

    if amount > 25_000 do
      "UNDER_REVIEW"
    else
      "PENDING_RISK"
    end
  end

  @impl true
  def assess_risk(app, bank_profile) do
    amount = to_float(get(app, "amount") || Map.get(app, :amount))
    income = to_float(get(app, "monthly_income") || Map.get(app, :monthly_income))
    total_debt = to_float(Map.get(bank_profile, :total_debt, 0))
    avg_balance = to_float(Map.get(bank_profile, :avg_balance, 0))

    external_score =
      Map.get(bank_profile, :score) ||
        Map.get(bank_profile, :credit_score, 680)

    # debt-to-income
    dti = safe_ratio(total_debt, income)
    # amount-to-income
    ati = safe_ratio(amount, income)

    raw_score =
      external_score * 0.4 +
        (850.0 - dti * 10.0 - ati * 7.0 + avg_balance / 1500.0) * 0.6

    score =
      raw_score
      |> trunc()
      |> clamp(300, 850)

    final_status =
      cond do
        score >= 730 -> "APPROVED"
        score >= 650 -> "UNDER_REVIEW"
        true -> "REJECTED"
      end

    %{score: score, final_status: final_status}
  end

  ## Helpers privados

  defp looks_like_spanish_dni?(value) do
    String.match?(value, ~r/^\d{8}[A-Z]$/)
  end

  defp get(map, key) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_integer(n) or is_float(n), do: n * 1.0

  defp to_float(s) when is_binary(s) do
    case Float.parse(s) do
      {v, _} -> v
      :error -> 0.0
    end
  end

  defp to_float(_), do: 0.0

  defp safe_ratio(_val, income) when income <= 0, do: 0.0
  defp safe_ratio(val, income), do: val / income

  defp clamp(v, min, max) when v < min, do: min
  defp clamp(v, min, max) when v > max, do: max
  defp clamp(v, _min, _max), do: v
end
