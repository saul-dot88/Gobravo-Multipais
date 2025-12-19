defmodule BravoMultipais.CreditApplications do
  @moduledoc """
  Contexto de alto nivel para trabajar con solicitudes de crédito.

  Expone funciones “limpias” para el resto de la app (LiveViews, APIs),
  delegando la lógica a:

    * `BravoMultipais.CreditApplications.Queries` – lecturas/queries.
    * `BravoMultipais.CreditApplications.Commands` – comandos/escritura.
  """

  alias BravoMultipais.CreditApplications.{Application, Commands, Queries}

  @type filter :: map()
  @type params :: map()
  @type id :: Ecto.UUID.t() | String.t()

  # ==========
  # Lecturas
  # ==========

  @doc """
  Lista solicitudes de crédito según el filtro dado (modelo interno).
  """
  @spec list_applications(filter) :: [Application.t()]
  def list_applications(filter \\ %{}) do
    Queries.list_applications(filter)
  end

  @doc """
  Lista solicitudes en formato público (DTO para API).
  """
  @spec list_applications_public(filter) :: [map()]
  def list_applications_public(filter \\ %{}) do
    filter
    |> list_applications()
    |> Enum.map(&to_public/1)
  end

  @doc """
  Obtiene una aplicación por ID (modelo interno).
  """
  @spec get_application(id) :: Application.t() | nil
  def get_application(id) do
    Queries.get_application(id)
  end

  @doc """
  Obtiene una aplicación por ID, lanzando si no existe.
  """
  @spec get_application!(id) :: Application.t()
  def get_application!(id) do
    case get_application(id) do
      nil -> raise Ecto.NoResultsError, queryable: Application
      app -> app
    end
  end

  @doc """
  Obtiene una aplicación por ID y la proyecta al formato público.

  Devuelve `nil` si no existe.
  """
  @spec get_application_public(id) :: map() | nil
  def get_application_public(id) do
    case get_application(id) do
      nil -> nil
      %Application{} = app -> to_public(app)
    end
  end

  # ==========
  # Comandos
  # ==========

  @doc """
  Crea una solicitud de crédito, normalizando parámetros y
  ejecutando todas las reglas de negocio.

  Internamente delega en `Commands.create_application/1`.
  """
  @spec create_application(params) :: {:ok, Application.t()} | {:error, term()}
  def create_application(params) when is_map(params) do
    Commands.create_application(params)
  end

  def create_application(_), do: {:error, :invalid_payload}

  # ==========
  # Proyección pública
  # ==========

  @doc """
  Proyección “pública” de una `Application`.

  Aquí decides qué campos exponer (evita filtrar bank_profile completo si no quieres
  sacar info sensible).
  """
  @spec to_public(Application.t()) :: map()
  def to_public(%Application{} = app) do
    base =
      %{
        id: app.id,
        country: app.country,
        full_name: app.full_name,
        status: app.status,
        risk_score: app.risk_score,
        amount: app.amount,
        monthly_income: app.monthly_income,
        inserted_at: app.inserted_at
      }

    # Si quieres exponer algo del perfil bancario, hazlo “sanitizado”:
    bank_profile =
      case app.bank_profile do
        nil ->
          nil

        profile when is_map(profile) ->
          Map.take(profile, ["external_id", "total_debt", "avg_balance", "currency"])
      end

    Map.put(base, :bank_profile, bank_profile)
  end
end
