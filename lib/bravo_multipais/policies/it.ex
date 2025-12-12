defmodule BravoMultipais.Policies.IT do
  @behaviour BravoMultipais.Policies.Policy

  @impl true
  def validate_document(doc) when is_map(doc) do
    cf = get(doc, "codice_fiscale")

    cond do
      is_binary(cf) and String.length(cf) >= 11 ->
        :ok

      true ->
        {:error, :invalid_codice_fiscale}
    end
  end

  @impl true
  def business_rules(app, bank_profile) do
    amount = to_float(app.amount)
    income = to_float(app.monthly_income)
    total_debt = to_float(Map.get(bank_profile, :total_debt, 0))

    cond do
      income <= 0 ->
        {:error, :invalid_income}

      amount > income * 15 ->
        {:error, :amount_too_high_relative_to_income}

      total_debt / income > 6 ->
        {:error, :debt_to_income_too_high}

      true ->
        :ok
    end
  end

  @impl true
  def next_status_on_creation(app, _bank_profile) do
    amount = to_float(app.amount)

    if amount > 25_000 do
      "UNDER_REVIEW"
    else
      "PENDING_RISK"
    end
  end

  # Helpers
  defp get(map, key) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  rescue
    ArgumentError ->
      Map.get(map, key)
  end

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_number(n), do: n * 1.0
  defp to_float(_), do: 0.0
end
