defmodule BravoMultipais.Policies do
  @moduledoc """
  Entry point para las políticas por país.
  """

  @type country :: String.t()

  @spec policy_for(country | atom) :: module
  def policy_for(country) when is_atom(country) do
    country
    |> Atom.to_string()
    |> policy_for()
  end

  def policy_for(country) when is_binary(country) do
    case String.upcase(country) do
      "ES" -> BravoMultipais.Policies.ES
      "IT" -> BravoMultipais.Policies.IT
      "PT" -> BravoMultipais.Policies.PT
      other ->
        raise ArgumentError, "Unsupported country #{inspect(other)} in policy_for/1"
    end
  end
end
