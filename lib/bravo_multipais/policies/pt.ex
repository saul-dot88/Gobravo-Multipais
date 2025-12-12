defmodule BravoMultipais.Policies.PT do
  @behaviour BravoMultipais.Policies.Policy

  @impl true
  def validate_document(doc) when is_map(doc) do
    nif = get(doc, "nif")

    cond do
      is_binary(nif) and String.length(nif) == 9 and String.match?(nif, ~r/^\d+$/) ->
        :ok

      true ->
        {:error, :invalid_nif}
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

      amount > income * 12 ->
        {:error, :amount_too_high_relative_to_income}

      total_debt / income > 7 ->
        {:error, :debt_to_income_too_high}

      true ->
        :ok
    end
  end

  @impl true
  def next_status_on_creation(app, bank_profile) do
    amount = to_float(app.amount)
    avg_balance = to_float(Map.get(bank_profile, :avg_balance, 0))

    cond do
      amount > 15_000 and avg_balance < amount / 2 ->
        "UNDER_REVIEW"

      true ->
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
