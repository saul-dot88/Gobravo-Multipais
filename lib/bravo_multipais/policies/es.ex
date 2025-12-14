defmodule BravoMultipais.Policies.ES do
  @behaviour BravoMultipais.Policies.Policy

  @min_income        500.0
  @max_amount_factor 18.0
  @max_dti           8.0

  @impl true
  def validate_document(doc) when is_map(doc) do
    dni = get(doc, "dni")
    nif = get(doc, "nif")
    nie = get(doc, "nie")

    cond do
      is_binary(dni) and String.length(dni) >= 8 -> :ok
      is_binary(nif) and String.length(nif) >= 8 -> :ok
      is_binary(nie) and String.length(nie) >= 8 -> :ok
      true -> {:error, :invalid_spanish_document}
    end
  end

  @impl true
  def business_rules(app, bank_profile) do
    amount     = app        |> field(:amount)          |> to_float()
    income     = app        |> field(:monthly_income)  |> to_float()
    total_debt = bank_profile |> field(:total_debt)    |> to_float()

    cond do
      income <= 0.0 ->
        {:error, :invalid_income}

      income < @min_income ->
        {:error, {:invalid_income, :below_minimum_income}}

      amount <= 0.0 ->
        {:error, :invalid_amount}

      amount > income * @max_amount_factor ->
        {:error, :amount_too_high_relative_to_income}

      safe_ratio(total_debt, income) > @max_dti ->
        {:error, :debt_to_income_too_high}

      true ->
        :ok
    end
  end

  @impl true
  def next_status_on_creation(app, bank_profile) do
    amount     = app        |> field(:amount)       |> to_float()
    total_debt = bank_profile |> field(:total_debt) |> to_float()

    cond do
      amount > 20_000.0 or total_debt > 30_000.0 ->
        "UNDER_REVIEW"

      true ->
        "PENDING_RISK"
    end
  end

  @impl true
  def assess_risk(app, bank_profile) do
    amount      = app        |> field(:amount)         |> to_float()
    income      = app        |> field(:monthly_income) |> to_float()
    total_debt  = bank_profile |> field(:total_debt)   |> to_float()
    avg_balance = bank_profile |> field(:avg_balance)  |> to_float()

    dti = safe_ratio(total_debt, income)  # deuda / ingreso
    ati = safe_ratio(amount, income)      # monto / ingreso

    raw_score =
      850.0
      - dti * 12.0
      - ati * 8.0
      + avg_balance / 1_000.0

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

  ## ------------- Helpers -------------

  # Para documentos (usa strings como "dni", "nif", etc.)
  defp get(map, key) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end

  # Para campos genéricos de app / bank_profile (soporta struct o map, atom o string)
  defp field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp field(_other, _key), do: nil

  # Conversiones a float tolerantes: Decimal, número, string "7000", etc.
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

  # ratio seguro: si ingreso <= 0 devolvemos 0 para no explotar
  defp safe_ratio(_val, income) when income <= 0.0, do: 0.0
  defp safe_ratio(val, income), do: val / income

  defp clamp(v, min, _max) when v < min, do: min
  defp clamp(v, _min, max) when v > max, do: max
  defp clamp(v, _min, _max), do: v
end
