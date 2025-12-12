defmodule BravoMultipais.Policies.Factory do
  @moduledoc """
  Selecciona la política correspondiente según el país.
  """
  alias BravoMultipais.Policies.{ES, IT, PT}

  def policy_for("ES"), do: ES
  def policy_for("IT"), do: IT
  def policy_for("PT"), do: PT

  # Por si en algún momento llega el país como átomo o minúsculas
  def policy_for(:ES), do: ES
  def policy_for(:IT), do: IT
  def policy_for(:PT), do: PT
  def policy_for(country) when is_binary(country), do: country |> String.upcase() |> policy_for()
end
