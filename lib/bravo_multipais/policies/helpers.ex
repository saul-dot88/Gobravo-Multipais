defmodule BravoMultipais.Policies.Helpers do
  @moduledoc """
  Helpers comunes para las políticas por país.
  """

  alias Decimal, as: D

  # Busca una clave string o atom en un map/struct
  def fetch_field(data, key_str, key_atom \\ nil) do
    key_atom = key_atom || String.to_atom(key_str)

    Map.get(data, key_str) ||
      Map.get(data, key_atom)
  end

  # Convierte strings/int/float/Decimal a Decimal
  def to_decimal(nil, default \\ D.new("0")), do: default
  def to_decimal(%D{} = d, _default), do: d
  def to_decimal(v, _default) when is_integer(v), do: D.new(v)
  def to_decimal(v, _default) when is_float(v), do: D.from_float(v)
  def to_decimal(v, default) when is_binary(v) do
    case D.new(v) do
      %D{} = d -> d
      _ -> default
    end
  rescue
    _ -> default
  end

  def to_decimal(_other, default), do: default

  # DTI = amount / monthly_income (protegiendo división entre 0)
  def dti(attrs) do
    amount =
      attrs
      |> fetch_field("amount", :amount)
      |> to_decimal(D.new("0"))

    income =
      attrs
      |> fetch_field("monthly_income", :monthly_income)
      |> to_decimal(D.new("0"))

    case D.cmp(income, D.new("0")) do
      :gt -> D.div(amount, income)
      _   -> D.new("1.0") # si income 0 asumimos riesgo máximo
    end
  end

  # Clampa un entero en [min, max]
  def clamp_int(value, min, max) do
    value
    |> max(min)
    |> min(max)
  end
end
