defmodule BravoMultipais.CreditApplications.Commands do
  @moduledoc """
  Capa de comandos para manejar el ciclo de vida de las solicitudes de crédito.

  Flujo típico de `create_application/1`:

    * Extrae y normaliza parámetros de entrada (form/API).
    * Normaliza el documento según el país (si viene como string).
    * O acepta el documento ya normalizado (si viene como mapa).
    * Resuelve la policy por país y valida el documento.
    * Consulta el perfil bancario simulado (`Bank.fetch_profile/2`).
    * Aplica reglas de negocio (`Policies.policy_for/1`).
    * Persiste la solicitud y encola un job de riesgo en Oban (atómico).
  """

  alias BravoMultipais.{Bank, Repo}
  alias BravoMultipais.Bank.Normalizer
  alias BravoMultipais.CreditApplications.Application
  alias BravoMultipais.Policies
  alias BravoMultipais.Workers.EvaluateRisk, as: EvaluateRiskWorker
  alias BravoMultipais.CreditApplications.{Events, EventTypes}

  @typedoc "Parámetros crudos que vienen del formulario LiveView o de la API"
  @type params :: map()

  @typedoc """
  Razones de error posibles al crear una aplicación.

  * `:invalid_payload` – falta country o document.
  * `{:invalid_changeset, Ecto.Changeset.t()}` – errores de validación.
  * `{:job_enqueue_failed, term()}` – fallo al encolar el job de riesgo.
  * `{:policy_error, term()}` – error de reglas de negocio / documento.
  * `{:bank_error, term()}` – fallo al obtener el perfil bancario.
  * `{:unexpected_error, term()}` – cualquier otro error no contemplado.
  """
  @type error_reason ::
          :invalid_payload
          | {:invalid_changeset, Ecto.Changeset.t()}
          | {:job_enqueue_failed, term()}
          | {:policy_error, term()}
          | {:bank_error, term()}
          | {:unexpected_error, term()}

  @spec create_application(params, keyword()) :: {:ok, Application.t()} | {:error, error_reason}
  def create_application(params, opts \\ [])

  def create_application(params, opts) when is_map(params) and is_list(opts) do
    source = Keyword.get(opts, :source, "system")

    country = fetch(params, "country")
    full_name = fetch(params, "full_name")
    amount = fetch(params, "amount")
    monthly_income = fetch(params, "monthly_income")

    raw_document =
      fetch(params, "document") ||
        fetch(params, "document_value")

    if is_nil(country) or is_nil(raw_document) do
      {:error, :invalid_payload}
    else
      normalized_country =
        country
        |> to_string()
        |> String.trim()
        |> String.upcase()

      normalized_full_name =
        full_name
        |> to_string()
        |> String.trim()

      with {:ok, doc_map} <- normalize_document(normalized_country, raw_document),
           policy <- Policies.policy_for(normalized_country),
           :ok <- ok_or_policy_error(policy.validate_document(doc_map)),
           {:ok, bank_profile} <-
             ok_or_bank_error(
               Bank.fetch_profile(normalized_country, %{
                 country: normalized_country,
                 document: doc_map
               })
             ),
           :ok <-
             ok_or_policy_error(
               policy.business_rules(
                 %{
                   country: normalized_country,
                   full_name: normalized_full_name,
                   amount: amount,
                   monthly_income: monthly_income,
                   document: doc_map
                 },
                 bank_profile
               )
             ),
           {:ok, app} <-
             persist_and_enqueue(
               %{
                 country: normalized_country,
                 full_name: normalized_full_name,
                 amount: amount,
                 monthly_income: monthly_income,
                 document: doc_map
               },
               bank_profile,
               policy,
               source
             ) do
        {:ok, app}
      else
        {:error, reason} -> {:error, reason}
        other -> {:error, {:unexpected_error, other}}
      end
    end
  end

  def create_application(_params, _opts), do: {:error, :invalid_payload}

  # =====================
  # Documento: normalización mínima por país
  # =====================

  defp normalize_document(country, raw) when is_binary(country) do
    cond do
      is_map(raw) ->
        normalize_document_map(country, raw)

      is_binary(raw) ->
        {:ok, build_document_map(country, raw)}

      true ->
        {:ok, build_document_map(country, to_string(raw))}
    end
  end

  # Si viene un map, intentamos:
  # 1) si ya trae la key esperada (dni/codice_fiscale/nif) => ok
  # 2) si trae "raw" => reconstruimos
  # 3) si no, error :missing_document
  defp normalize_document_map(country, %{} = doc) do
    expected_key =
      case country do
        "ES" -> "dni"
        "IT" -> "codice_fiscale"
        "PT" -> "nif"
        _ -> nil
      end

    cond do
      is_nil(expected_key) ->
        {:error, {:policy_error, {:unsupported_country, country}}}

      Map.has_key?(doc, expected_key) or Map.has_key?(doc, String.to_atom(expected_key)) ->
        value = fetch(doc, expected_key)

        if is_nil(value) or String.trim(to_string(value)) == "" do
          {:error, {:policy_error, :missing_document}}
        else
          {:ok, build_document_map(country, value)}
        end

      Map.has_key?(doc, "raw") or Map.has_key?(doc, :raw) ->
        raw = fetch(doc, "raw")

        if is_nil(raw) or String.trim(to_string(raw)) == "" do
          {:error, {:policy_error, :missing_document}}
        else
          {:ok, build_document_map(country, raw)}
        end

      true ->
        {:error, {:policy_error, :missing_document}}
    end
  end

  defp build_document_map(country, value) do
    raw =
      value
      |> to_string()
      |> String.trim()

    normalized =
      raw
      |> String.upcase()

    case country do
      "ES" ->
        # DNI: 8 dígitos + letra, dejamos mayúsculas
        %{"dni" => normalized, "raw" => raw}

      "IT" ->
        # Codice Fiscale suele usarse en mayúsculas
        %{"codice_fiscale" => normalized, "raw" => raw}

      "PT" ->
        # NIF: sólo dígitos (por si meten espacios/guiones)
        digits_only = normalized |> String.replace(~r/[^0-9]/, "")
        %{"nif" => digits_only, "raw" => raw}

      _ ->
        %{"raw" => raw}
    end
  end

  # =====================
  # Helpers de lectura
  # =====================

  defp fetch(params, key) when is_binary(key) do
    Map.get(params, key) ||
      case safe_existing_atom(key) do
        nil -> nil
        atom -> Map.get(params, atom)
      end
  end

  defp safe_existing_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  # =====================
  # Normalización de errores
  # =====================

  defp ok_or_policy_error(:ok), do: :ok
  defp ok_or_policy_error({:error, reason}), do: {:error, {:policy_error, reason}}
  defp ok_or_policy_error(other), do: {:error, {:policy_error, other}}

  defp ok_or_bank_error({:ok, profile}), do: {:ok, profile}
  defp ok_or_bank_error({:error, reason}), do: {:error, {:bank_error, reason}}
  defp ok_or_bank_error(other), do: {:error, {:bank_error, other}}

  # =====================
  # Persistencia + Oban (ATÓMICO)
  # =====================

  @spec persist_and_enqueue(map(), map(), module(), String.t()) ::
          {:ok, Application.t()} | {:error, error_reason}
  defp persist_and_enqueue(attrs, bank_profile, policy_module, source) do
    initial_status = policy_module.next_status_on_creation(attrs, bank_profile)

    changes =
      attrs
      |> Map.take([:country, :full_name, :document, :amount, :monthly_income])
      |> Map.put(:status, initial_status)
      |> Map.put(:bank_profile, bank_profile)

    changeset =
      %Application{}
      |> Application.changeset(changes)

    Repo.transaction(fn ->
      case Repo.insert(changeset) do
        {:ok, app} ->
          _ =
            Events.record(
              app.id,
              "created",
              %{
                country: app.country,
                status: app.status
              }, source: source)

          _ =
            Events.record(
              app.id,
              "document_validated",
              %{
                country: app.country,
                doc_type: doc_type_for_country(app.country)
              }, source: source)

          case EvaluateRiskWorker.enqueue(app.id) do
            :ok ->
              _ =
                Events.record(
                  app.id,
                  "risk_enqueued",
                  %{
                    queue: "risk"
                  }, source: source)

              app

            {:error, reason} ->
              Repo.rollback({:job_enqueue_failed, reason})

            other ->
              Repo.rollback({:job_enqueue_failed, other})
          end

        {:error, cs} ->
          Repo.rollback({:invalid_changeset, cs})
      end
    end)
    |> case do
      {:ok, app} ->
        {:ok, app}

      {:error, {:invalid_changeset, cs}} ->
        {:error, {:invalid_changeset, cs}}

      {:error, {:job_enqueue_failed, reason}} ->
        {:error, {:job_enqueue_failed, reason}}
    end
  end

  # (en el mismo módulo Commands)
  defp doc_type_for_country("ES"), do: "dni"
  defp doc_type_for_country("IT"), do: "codice_fiscale"
  defp doc_type_for_country("PT"), do: "nif"
  defp doc_type_for_country(_), do: "raw"
end
