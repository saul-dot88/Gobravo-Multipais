defmodule BravoMultipais.Policies.PT do
  @moduledoc """
  Políticas de validación y riesgo para Portugal.

  Implementa el behaviour `BravoMultipais.Policies.Policy`.
  """

  @behaviour BravoMultipais.Policies.Policy

  ## Callbacks

  @impl true
  def validate_document(doc) when is_map(doc) do
    nif =
      doc
      |> get("nif")
      |> to_string()
      |> String.trim()

    cond do
      nif == "" ->
        {:error, :missing_document}

      not String.match?(nif, ~r/^\d{9}$/) ->
        {:error, :invalid_nif_format}

      not valid_nif_checksum?(nif) ->
        {:error, :invalid_nif_checksum}

      true ->
        :ok
    end
  end

  @impl true
  def business_rules(app, bank_profile) do
    amount = to_float(get(app, "amount") || Map.get(app, :amount))
    income = to_float(get(app, "monthly_income") || Map.get(app, :monthly_income))
    total_debt = to_float(Map.get(bank_profile, :total_debt, 0))

    dti = safe_ratio(total_debt, income)

    cond do
      income < 500 ->
        {:error, :income_too_low}

      amount > income * 10 ->
        {:error, :amount_too_high_relative_to_income}

      dti > 7 ->
        {:error, :debt_to_income_too_high}

      true ->
        :ok
    end
  end

  @impl true
  def next_status_on_creation(app, bank_profile) do
    amount = to_float(get(app, "amount") || Map.get(app, :amount))
    income = to_float(get(app, "monthly_income") || Map.get(app, :monthly_income))
    external = Map.get(bank_profile, :score) || Map.get(bank_profile, :credit_score, 680)

    cond do
      amount > 18_000 ->
        "UNDER_REVIEW"

      external < 620 ->
        "UNDER_REVIEW"

      income < 700 ->
        "UNDER_REVIEW"

      true ->
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
        Map.get(bank_profile, :credit_score, 670)

    dti = safe_ratio(total_debt, income)
    ati = safe_ratio(amount, income)

    # PT: damos un poquito más peso al score externo
    raw_score =
      external_score * 0.6 +
        (850.0 - dti * 9.0 - ati * 6.0 + avg_balance / 1800.0) * 0.4

    score =
      raw_score
      |> trunc()
      |> clamp(300, 850)

    final_status =
      cond do
        score >= 720 -> "APPROVED"
        score >= 640 -> "UNDER_REVIEW"
        true -> "REJECTED"
      end

    %{score: score, final_status: final_status}
  end

  ## Helpers privados

  # Chequeo simple de NIF portugués (checksum estándar mod 11 simplificado)
  defp valid_nif_checksum?(nif) do
    digits =
      nif
      |> String.graphemes()
      |> Enum.map(&String.to_integer/1)

    # primeros 8 dígitos con peso 9..2
    {base, [check_digit]} = Enum.split(digits, 8)

    sum =
      base
      |> Enum.zip(9..2)
      |> Enum.reduce(0, fn {digit, weight}, acc -> acc + digit * weight end)

    mod11 = rem(sum, 11)

    expected =
      case 11 - mod11 do
        10 -> 0
        11 -> 0
        n -> n
      end

    check_digit == expected
  rescue
    _ -> false
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
