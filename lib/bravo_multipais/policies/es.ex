defmodule BravoMultipais.Policies.ES do
  @moduledoc """
  Políticas de validación y riesgo para España.

  Implementa el behaviour `BravoMultipais.Policies.Policy`.
  """

  @behaviour BravoMultipais.Policies.Policy

  ## Callbacks

  @impl true
  def validate_document(doc) when is_map(doc) do
    dni =
      doc
      |> get("dni")
      |> to_string()
      |> String.trim()
      |> String.upcase()

    cond do
      dni == "" ->
        {:error, :missing_document}

      not String.match?(dni, ~r/^\d{8}[A-Z]$/) ->
        {:error, :invalid_dni_format}

      not valid_dni_letter?(dni) ->
        {:error, :invalid_dni_letter}

      true ->
        :ok
    end
  end

  @impl true
  def business_rules(app, bank_profile) do
    amount       = to_float(get(app, "amount") || Map.get(app, :amount))
    income       = to_float(get(app, "monthly_income") || Map.get(app, :monthly_income))
    total_debt   = to_float(Map.get(bank_profile, :total_debt, 0))

    dti = safe_ratio(total_debt, income) # debt-to-income

    cond do
      income < 600 ->
        {:error, :income_too_low}

      amount > income * 12 ->
        {:error, :amount_too_high_relative_to_income}

      dti > 8 ->
        {:error, :debt_to_income_too_high}

      true ->
        :ok
    end
  end

  @impl true
  def next_status_on_creation(app, _bank_profile) do
    amount = to_float(get(app, "amount") || Map.get(app, :amount))
    income = to_float(get(app, "monthly_income") || Map.get(app, :monthly_income))

    cond do
      amount > 20_000 ->
        "UNDER_REVIEW"

      income < 800 ->
        "UNDER_REVIEW"

      true ->
        "PENDING_RISK"
    end
  end

  @impl true
  def assess_risk(app, bank_profile) do
    amount       = to_float(get(app, "amount") || Map.get(app, :amount))
    income       = to_float(get(app, "monthly_income") || Map.get(app, :monthly_income))
    total_debt   = to_float(Map.get(bank_profile, :total_debt, 0))
    avg_balance  = to_float(Map.get(bank_profile, :avg_balance, 0))

    external_score =
      Map.get(bank_profile, :score) ||
        Map.get(bank_profile, :credit_score, 680)

    dti = safe_ratio(total_debt, income)
    ati = safe_ratio(amount, income)

    # ES: un poco más conservador con DTI/ATI
    raw_score =
      external_score * 0.5 +
        (850.0 - dti * 12.0 - ati * 8.0 + avg_balance / 2000.0) * 0.5

    score =
      raw_score
      |> trunc()
      |> clamp(300, 850)

    final_status =
      cond do
        score >= 740 -> "APPROVED"
        score >= 660 -> "UNDER_REVIEW"
        true         -> "REJECTED"
      end

    %{score: score, final_status: final_status}
  end

  ## Helpers privados

  # DNI: 8 dígitos + letra, con chequeo de letra
  defp valid_dni_letter?(dni) do
    letters = 'TRWAGMYFPDXBNJZSQVHLCKE'

    <<number::binary-size(8), letter::binary-size(1)>> = dni

    case Integer.parse(number) do
      {n, ""} ->
        expected_letter =
          letters
          |> Enum.at(rem(n, 23))
          |> to_string()

        letter == expected_letter

      _ ->
        false
    end
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
