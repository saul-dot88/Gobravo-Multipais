defmodule BravoMultipais.Bank.Factory do
  @moduledoc """
  Elige el proveedor bancario según el país.
  """
  alias BravoMultipais.Bank.{ES, IT, PT}

  def provider_for("ES"), do: ES
  def provider_for("IT"), do: IT
  def provider_for("PT"), do: PT

  def provider_for(:ES), do: ES
  def provider_for(:IT), do: IT
  def provider_for(:PT), do: PT

  def provider_for(country) when is_binary(country),
    do: country |> String.upcase() |> provider_for()
end
