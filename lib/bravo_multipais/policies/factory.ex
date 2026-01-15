defmodule BravoMultipais.Policies.Factory do
  @moduledoc """
  DEPRECADO.

  Este módulo existía como selector alterno de policy.
  Mantenerlo como wrapper evita confusión y permite migración gradual.

  Usa `BravoMultipais.Policies.policy_for/1`.
  """

  @deprecated "Use BravoMultipais.Policies.policy_for/1"
  def policy_for(country), do: BravoMultipais.Policies.policy_for(country)
end
