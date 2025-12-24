defmodule BravoMultipais.BankCache do
  @moduledoc """
  Caché simple para el perfil bancario (`bank_profile`) de una solicitud.

  La idea:
    * Modelamos el proveedor bancario como algo costoso.
    * Cacheamos el perfil por `application_id` usando Cachex (ETS).
    * Si el caché falla por cualquier motivo, hacemos fallback a la lógica normal.
  """

  alias BravoMultipais.Bank
  alias BravoMultipais.CreditApplications.Application

  @cache_name :bank_profile_cache

  @type profile :: map()

  @spec fetch_profile(Application.t()) :: profile
  def fetch_profile(%Application{} = app) do
    key = {:bank_profile, app.id}

    case Cachex.get(@cache_name, key) do
      {:ok, nil} ->
        profile = Bank.build_mock_profile(app.country, app)
        _ = Cachex.put(@cache_name, key, profile)
        profile

      {:ok, profile} ->
        profile

      {:error, _reason} ->
        # Si Cachex fallara, no queremos romper el flujo
        Bank.build_mock_profile(app.country, app)
    end
  end

  @doc """
  Invalida manualmente el caché para una solicitud dada.

  Útil si en el futuro hubiera un flujo donde el banco actualiza datos
  y necesitamos refrescar el perfil.
  """
  @spec invalidate(Application.t()) :: :ok | {:error, term()}
  def invalidate(%Application{id: id}) do
    Cachex.del(@cache_name, {:bank_profile, id})
  end
end
