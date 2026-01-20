defmodule BravoMultipais.Policies do
  @moduledoc """
  Entry point para políticas por país.

  Soporta versionado simple: country + version -> módulo policy.
  Ej: "ES" + "v1" => BravoMultipais.Policies.ES
  """

  @type country :: String.t()
  @type version :: String.t()
  @type policy_module :: module()

  # Registry simple: tus módulos actuales son "v1"
  @registry %{
    "ES" => %{"v1" => BravoMultipais.Policies.ES},
    "IT" => %{"v1" => BravoMultipais.Policies.IT},
    "PT" => %{"v1" => BravoMultipais.Policies.PT}
  }

  @spec default_version(country | atom) :: version
  def default_version(country) when is_atom(country),
    do: country |> Atom.to_string() |> default_version()

  def default_version(country) when is_binary(country) do
    versions = Application.get_env(:bravo_multipais, :policy_versions, %{})

    country_up = String.upcase(country)

    Map.get(versions, country_up) ||
      System.get_env("POLICY_VERSION_#{country_up}") ||
      "v1"
  end

  @spec policy_id(country | atom, version | nil) :: String.t()
  def policy_id(country, version \\ nil) do
    c = country |> to_string() |> String.upcase()
    v = version || default_version(c)
    "#{c}:#{v}"
  end

  @spec policy_for(country | atom, version | nil) :: policy_module
  def policy_for(country, version \\ nil)

  def policy_for(country, version) when is_atom(country),
    do: country |> Atom.to_string() |> policy_for(version)

  def policy_for(country, version) when is_binary(country) do
    c = String.upcase(country)
    v = version || default_version(c)

    case get_in(@registry, [c, v]) do
      nil ->
        raise ArgumentError,
              "Unsupported policy for country=#{inspect(c)} version=#{inspect(v)}"

      mod ->
        mod
    end
  end
end
