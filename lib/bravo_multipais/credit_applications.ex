defmodule BravoMultipais.CreditApplications do
  @moduledoc """
  Contexto público para el módulo de solicitudes de crédito.

  - Lecturas con filtros y paginación (`list_applications/2`).
  - Proyección pública de `Application` (`to_public/1`).
  - Comandos de creación (`create_application/1`) delegando a `Commands`.
  """

  import Ecto.Query, only: [from: 2, offset: 2, limit: 2]

  alias BravoMultipais.CreditApplications.{Application, Commands, Queries}
  alias BravoMultipais.Repo

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

  @type page_result :: %{
          entries: [map()],
          total: non_neg_integer(),
          page: pos_integer(),
          per_page: pos_integer(),
          total_pages: pos_integer()
        }

  # Campos que SÍ queremos exponer de bank_profile
  @allowed_bank_profile_fields ~w(external_id total_debt avg_balance currency)

  # ─────────────────────────────────────────────────────────────
  # Lecturas / queries
  # ─────────────────────────────────────────────────────────────

  @doc """
  Lista solicitudes aplicando filtros opcionales **sin paginación explícita**.

  Devuelve sólo la lista de aplicaciones en formato público.
  Internamente usa la versión paginada con `page: 1` y `per_page: 50`.
  """
  @spec list_applications(filters()) :: [map()]
  def list_applications(filters \\ %{}) do
    list_applications(filters, page: 1, per_page: 50).entries
  end

  @doc """
  Lista solicitudes con filtros + paginación.

  Devuelve un mapa con:

    * `:entries`      → lista de aplicaciones en formato público
    * `:total`        → total de registros que cumplen los filtros
    * `:page`         → página actual (1-based)
    * `:per_page`     → tamaño de página
    * `:total_pages`  → número total de páginas
  """
  @spec list_applications(filters(), keyword()) :: %{
          entries: [map()],
          page: pos_integer(),
          per_page: pos_integer(),
          total: non_neg_integer(),
          total_pages: pos_integer()
        }
  def list_applications(filters, opts) when is_list(opts) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    base =
      from a in Application,
        order_by: [desc: a.inserted_at]

    query =
      base
      |> maybe_filter_country(filters[:country])
      |> maybe_filter_status(filters[:status])
      |> maybe_filter_amount_range(filters[:min_amount], filters[:max_amount])
      |> maybe_filter_date_range(filters[:from_date], filters[:to_date])
      |> maybe_filter_only_evaluated(filters[:only_evaluated])

    total = Repo.aggregate(query, :count, :id)

    entries =
      query
      |> limit(^per_page)
      |> offset(^(per_page * max(page - 1, 0)))
      |> Repo.all()
      |> Enum.map(&to_public/1)

    total_pages =
      cond do
        total == 0 ->
          1

        per_page <= 0 ->
          1

        true ->
          Integer.floor_div(total + per_page - 1, per_page)
      end

    %{
      entries: entries,
      page: page,
      per_page: per_page,
      total: total,
      total_pages: total_pages
    }
  end

  # ── Filtros de query ─────────────────────────────

  defp maybe_filter_country(query, nil), do: query

  defp maybe_filter_country(query, country) do
    from a in query, where: a.country == ^country
  end

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status) do
    from a in query, where: a.status == ^status
  end

  defp maybe_filter_amount_range(query, nil, nil), do: query

  defp maybe_filter_amount_range(query, "" = _min, max),
    do: maybe_filter_amount_range(query, nil, max)

  defp maybe_filter_amount_range(query, min, "" = _max),
    do: maybe_filter_amount_range(query, min, nil)

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

  defp maybe_filter_date_range(query, "" = _from, to_date),
    do: maybe_filter_date_range(query, nil, to_date)

  defp maybe_filter_date_range(query, from_date, "" = _to),
    do: maybe_filter_date_range(query, from_date, nil)

  defp maybe_filter_date_range(query, from_date, nil) do
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

  # ── API pública delegada a Queries ──────────────────────────

  @doc """
  Versión pública de `list_applications/1` para API, delegada a `Queries`.

  Aquí asumimos que `Queries` ya hace la proyección adecuada para la API externa
  (puede usar `to_public/1` por dentro).
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

  @spec change_application(Application.t(), map()) :: Ecto.Changeset.t()
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
  @spec to_public(Application.t() | nil) :: map() | nil
  def to_public(nil), do: nil

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

    Map.put(base, :bank_profile, sanitize_bank_profile(app.bank_profile))
  end

 defp public_document(nil), do: nil

defp public_document(%{} = doc) do
  cond do
    # ES
    Map.has_key?(doc, "dni") -> doc["dni"]
    Map.has_key?(doc, :dni) -> doc[:dni]
    Map.has_key?(doc, "nif") -> doc["nif"]
    Map.has_key?(doc, :nif) -> doc[:nif]
    Map.has_key?(doc, "nie") -> doc["nie"]
    Map.has_key?(doc, :nie) -> doc[:nie]

    # IT
    Map.has_key?(doc, "codice_fiscale") -> doc["codice_fiscale"]
    Map.has_key?(doc, :codice_fiscale) -> doc[:codice_fiscale]

    # fallback
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

  # Sin perfil → devuelve nil
  defp sanitize_bank_profile(nil), do: nil

  # Perfil válido → normaliza claves a string y se queda con los campos permitidos
  defp sanitize_bank_profile(%{} = profile) do
    profile
    |> normalize_string_keys()
    |> Map.take(@allowed_bank_profile_fields)
  end

  # Cualquier otra cosa rara → nil
  defp sanitize_bank_profile(_), do: nil
end
