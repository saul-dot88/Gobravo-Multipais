defmodule BravoMultipais.CreditApplications do
  @moduledoc """
  Contexto público para el módulo de solicitudes de crédito.
  ...
  """

  import Ecto.Query, only: [from: 2]

  alias BravoMultipais.Repo
  alias BravoMultipais.CreditApplications.{Application, Commands, Queries}

  @type application :: Application.t()
  @type filters :: %{
          optional(:country) => String.t(),
          optional(:status) => String.t(),
          optional(:min_amount) => String.t() | number(),
          optional(:max_amount) => String.t() | number(),
          optional(:from_date) => String.t(),
          optional(:to_date) => String.t(),
          optional(:only_evaluated) => boolean()
        }

  # ─────────────────────────────────────────────────────────────
  # Lecturas / queries
  # ─────────────────────────────────────────────────────────────

  @doc """
  Lista solicitudes aplicando filtros opcionales.

  Esta versión se usa desde el LiveView (backoffice).
  """
  def list_applications(filters \\ %{}) do
    base =
      from a in Application,
        order_by: [desc: a.inserted_at]

    base
    |> maybe_filter_country(filters[:country])
    |> maybe_filter_status(filters[:status])
    |> maybe_filter_amount_range(filters[:min_amount], filters[:max_amount])
    |> maybe_filter_date_range(filters[:from_date], filters[:to_date])
    |> maybe_filter_only_evaluated(filters[:only_evaluated])
    |> Repo.all()
  end

  defp maybe_filter_country(query, nil), do: query

  defp maybe_filter_country(query, country) do
    from a in query, where: a.country == ^country
  end

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status) do
    from a in query, where: a.status == ^status
  end

  defp maybe_filter_amount_range(query, nil, nil), do: query

  defp maybe_filter_amount_range(query, min, nil) do
    from a in query, where: a.amount >= ^min
  end

  defp maybe_filter_amount_range(query, nil, max) do
    from a in query, where: a.amount <= ^max
  end

  defp maybe_filter_amount_range(query, min, max) do
    from a in query, where: a.amount >= ^min and a.amount <= ^max
  end

  defp maybe_filter_date_range(query, nil, nil), do: query

  defp maybe_filter_date_range(query, from_date, nil) do
    # "2025-12-20" -> ~N[2025-12-20 00:00:00]
    {:ok, from} = NaiveDateTime.from_iso8601("#{from_date} 00:00:00")

    from a in query,
      where: a.inserted_at >= ^from
  end

  defp maybe_filter_date_range(query, nil, to_date) do
    {:ok, to} = NaiveDateTime.from_iso8601("#{to_date} 23:59:59")

    from a in query,
      where: a.inserted_at <= ^to
  end

  defp maybe_filter_date_range(query, from_date, to_date) do
    {:ok, from} = NaiveDateTime.from_iso8601("#{from_date} 00:00:00")
    {:ok, to} = NaiveDateTime.from_iso8601("#{to_date} 23:59:59")

    from a in query,
      where: a.inserted_at >= ^from and a.inserted_at <= ^to
  end

  defp maybe_filter_only_evaluated(query, true) do
    from a in query, where: not is_nil(a.risk_score)
  end

  defp maybe_filter_only_evaluated(query, _), do: query

  @doc """
  Versión pública de `list_applications/1`, ya proyectada a JSON-safe.

  Esta se sigue delegando a `Queries`, para mantener separados
  los contratos de API pública y el backoffice.
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

  @spec create_application(map()) ::
          {:ok, application}
          | {:error, {:policy_error, term()}}
          | {:error, {:invalid_changeset, Ecto.Changeset.t()}}
          | {:error, term()}
  def create_application(params) do
    case Commands.create_application(params) do
      {:ok, app} ->
        {:ok, app}

      {:error, {:policy_error, _} = e} ->
        {:error, e}

      {:error, :income_too_low} ->
        {:error, {:policy_error, :income_too_low}}

      {:error, {:invalid_changeset, %Ecto.Changeset{} = changeset}} ->
        {:error, {:invalid_changeset, changeset}}

      {:error, other} ->
        {:error, other}
    end
  end

  @spec change_application(Application.t() | %Application{}, map()) :: Ecto.Changeset.t()
  def change_application(app \\ %Application{}, attrs \\ %{}) do
    Application.changeset(app, attrs)
  end

  # ─────────────────────────────────────────────────────────────
  # Proyección pública
  # ─────────────────────────────────────────────────────────────

  @doc """
  Proyección pública de una Application.

  - Expone sólo los campos de lectura.
  - Sanitiza el `bank_profile` para no filtrar datos internos.
  """
  def to_public(%Application{} = app) do
    base = %{
      id: app.id,
      country: app.country,
      full_name: app.full_name,
      status: app.status,
      risk_score: app.risk_score,
      amount: app.amount,
      monthly_income: app.monthly_income,
      inserted_at: app.inserted_at,
      document: public_document(app.document),
      external_reference: app.external_reference,
      updated_at: app.updated_at
    }

    bank_profile =
      case app.bank_profile do
        nil ->
          nil

        %{} = bp ->
          bp
          |> normalize_string_keys()
          |> Map.take(~w(external_id total_debt avg_balance currency))
      end

    Map.put(base, :bank_profile, bank_profile)
  end

  defp public_document(nil), do: nil

  defp public_document(%{} = doc) do
    # Aquí deja tu lógica actual (NIF, codice_fiscale, etc),
    # o si ya la tienes, respétala. Ejemplo genérico:
    cond do
      Map.has_key?(doc, "nif") -> doc["nif"]
      Map.has_key?(doc, :nif) -> doc[:nif]
      Map.has_key?(doc, "codice_fiscale") -> doc["codice_fiscale"]
      Map.has_key?(doc, :codice_fiscale) -> doc[:codice_fiscale]
      true -> nil
    end
  end

  defp normalize_string_keys(map) do
    map
    |> Enum.into(%{}, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  # ── Sanitizado de bank_profile ─────────────────

  # Sin perfil → devuelve nil pero **con la key** presente
  defp sanitize_bank_profile(nil), do: nil

  # Perfil válido → nos quedamos sólo con las cosas "externas"
  defp sanitize_bank_profile(%{} = profile) do
    profile
    |> Map.take([
      :country,
      :currency,
      :score,
      :external_id,
      :total_debt,
      :avg_balance
    ])
  end

  # Cualquier otra cosa rara → nil
  defp sanitize_bank_profile(_), do: nil
end
