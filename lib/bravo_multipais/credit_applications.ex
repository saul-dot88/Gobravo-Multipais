defmodule BravoMultipais.CreditApplications do
  @moduledoc """
  Contexto público para el módulo de solicitudes de crédito.

  Expone una API estable para controladores, LiveViews y cualquier otra capa
  externa, delegando la lógica real a:

    * `BravoMultipais.CreditApplications.Commands`
    * `BravoMultipais.CreditApplications.Queries`

  Además define una proyección pública (`to_public/1`) para exponer
  las solicitudes hacia APIs externas.
  """

  alias BravoMultipais.CreditApplications.{Application, Commands, Queries}

  @type application :: Application.t()
  @type filters :: %{optional(:country) => String.t(), optional(:status) => String.t()}

  # ─────────────────────────────────────────────────────────────
  # Lecturas / queries
  # ─────────────────────────────────────────────────────────────

  @doc """
  Lista solicitudes aplicando filtros opcionales.

  Acepta tanto mapas con keys string (params de Plug/conn) como
  mapas con keys atom (`:country`, `:status`).
  """
  @spec list_applications(map()) :: [application]
  def list_applications(params \\ %{}) do
    filters =
      %{}
      |> maybe_put_filter(params, :country)
      |> maybe_put_filter(params, :status)

    Queries.list_applications(filters)
  end

  @doc """
  Versión pública de `list_applications/1`, ya proyectada a JSON-safe.

  Devuelve una lista de maps tal como se exponen en la API.
  """
  @spec list_applications_public(map()) :: [map()]
  def list_applications_public(params \\ %{}) do
    Queries.list_applications(params)
  end

  @doc """
  Obtiene una aplicación por id, o `nil` si no existe.
  """
  @spec get_application(Ecto.UUID.t()) :: application | nil
  def get_application(id), do: Queries.get_application(id)

  @doc """
  Igual que `get_application/1` pero lanza si no existe.
  """
  @spec get_application!(Ecto.UUID.t()) :: application
  def get_application!(id), do: Queries.get_application!(id)

  @doc """
  Devuelve una versión “pública” de la aplicación, lista para exponer en APIs.

  Si no existe la aplicación, devuelve `nil`.
  """
  @spec get_application_public(Ecto.UUID.t()) :: map() | nil
  def get_application_public(id) do
    case Queries.get_application(id) do
      %Application{} = app -> to_public(app)
      nil -> nil
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Comandos / escritura
  # ─────────────────────────────────────────────────────────────

  @doc """
  Crea una solicitud de crédito a través del módulo de comandos.

  Delegamos a `Commands.create_application/1` sin cambiar el contrato, de forma
  que los controladores puedan pattern-matchear:

    * `{:ok, %Application{}}`
    * `{:error, {:policy_error, reason}}`
    * `{:error, {:invalid_changeset, %Ecto.Changeset{}}}`
    * `{:error, reason}` (otros errores de dominio)
  """
  @spec create_application(map()) ::
          {:ok, application}
          | {:error, {:policy_error, term()}}
          | {:error, {:invalid_changeset, Ecto.Changeset.t()}}
          | {:error, term()}
  def create_application(params) do
    case Commands.create_application(params) do
      {:ok, app} ->
        {:ok, app}

      # ya viene marcado como policy_error
      {:error, {:policy_error, _} = e} ->
        {:error, e}

      # errores de negocio “crudos” del dominio
      {:error, :income_too_low} ->
        {:error, {:policy_error, :income_too_low}}

      # cambioset inválido desde Commands.persist_and_enqueue/3
      {:error, {:invalid_changeset, %Ecto.Changeset{} = changeset}} ->
        {:error, {:invalid_changeset, changeset}}

      # cualquier otra cosa, la dejamos pasar tal cual
      {:error, other} ->
        {:error, other}
    end
  end

  @doc """
  Devuelve un changeset para formularios LiveView (opcional).

  No lo estamos usando aún en tu LiveView actual, pero es estándar de contexto.
  """
  @spec change_application(Application.t() | %Application{}, map()) :: Ecto.Changeset.t()
  def change_application(app \\ %Application{}, attrs \\ %{}) do
    Application.changeset(app, attrs)
  end

  # ─────────────────────────────────────────────────────────────
  # Proyección pública
  # ─────────────────────────────────────────────────────────────

  @doc """
  Proyección “segura” para exponer una solicitud en JSON.

  Ojo: aquí puedes decidir qué campos NO quieres exponer hacia fuera
  (por ej. `bank_profile` completo).
  """
  @spec to_public(Application.t()) :: map()
  def to_public(%Application{} = app) do
    %{
      id: app.id,
      country: app.country,
      full_name: app.full_name,
      document: app.document,
      amount: app.amount,
      monthly_income: app.monthly_income,
      status: app.status,
      risk_score: app.risk_score,
      external_reference: app.external_reference,
      inserted_at: app.inserted_at,
      updated_at: app.updated_at
      # Si en un futuro quieres exponer parte de bank_profile,
      # aquí podrías hacer algo como:
      # bank_profile: Map.take(app.bank_profile || %{}, ["score", "total_debt"])
    }
  end

  # ─────────────────────────────────────────────────────────────
  # Helpers internos
  # ─────────────────────────────────────────────────────────────

  # Lee country/status indistintamente como "country" / :country, y
  # ignora valores vacíos.
  defp maybe_put_filter(acc, params, key) do
    val =
      Map.get(params, key) ||
        Map.get(params, Atom.to_string(key))

    case val do
      nil -> acc
      "" -> acc
      v -> Map.put(acc, key, v)
    end
  end
end
