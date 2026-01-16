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

  @spec create_application(params) :: {:ok, Application.t()} | {:error, error_reason}
  def create_application(params) when is_map(params) do
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

      doc_map =
        cond do
          is_map(raw_document) ->
            raw_document

          is_binary(raw_document) ->
            Normalizer.build_document_map(normalized_country, raw_document)

          true ->
            Normalizer.build_document_map(normalized_country, to_string(raw_document))
        end

      attrs = %{
        country: normalized_country,
        full_name: normalized_full_name,
        amount: amount,
        monthly_income: monthly_income,
        document: doc_map
      }

      with policy <- Policies.policy_for(attrs.country),
           :ok <- ok_or_policy_error(policy.validate_document(attrs.document)),
           {:ok, bank_profile} <- ok_or_bank_error(Bank.fetch_profile(attrs.country, attrs)),
           :ok <- ok_or_policy_error(policy.business_rules(attrs, bank_profile)),
           {:ok, app} <- persist_and_enqueue(attrs, bank_profile, policy) do
        {:ok, app}
      else
        {:error, reason} ->
          {:error, reason}

        other ->
          {:error, {:unexpected_error, other}}
      end
    end
  end

  def create_application(_), do: {:error, :invalid_payload}

  # =====================
  # Helpers de lectura
  # =====================

  # Lee clave como string o atom existente; si no existe, devuelve nil.
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

  @spec persist_and_enqueue(map(), map(), module()) ::
          {:ok, Application.t()} | {:error, error_reason}
  defp persist_and_enqueue(attrs, bank_profile, policy_module) do
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
          case EvaluateRiskWorker.enqueue(app.id) do
            {:ok, _job} ->
              app

            :ok ->
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
end
