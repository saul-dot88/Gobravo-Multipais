defmodule BravoMultipais.CreditApplications.Commands do
  @moduledoc """
  Capa de comandos para manejar el ciclo de vida de las solicitudes de crédito.

  Flujo:
  - Extrae y normaliza parámetros de entrada (form/API).
  - Normaliza documento según el país (si viene como string).
  - O acepta el documento ya normalizado (si viene como mapa).
  - Resuelve policy por país y valida documento.
  - Consulta perfil bancario simulado.
  - Aplica reglas de negocio.
  - Persiste solicitud y encola job de riesgo en Oban.
  """

  alias BravoMultipais.{Repo, Bank}
  alias BravoMultipais.Bank.Normalizer
  alias BravoMultipais.CreditApplications.Application
  alias BravoMultipais.Policies

  @type params :: map()
  @type error_reason :: term()

  @spec create_application(params) :: {:ok, Application.t()} | {:error, error_reason}
  def create_application(params) when is_map(params) do
    # Debug opcional:
    IO.inspect(params, label: "create_application params")

    country        = fetch(params, "country")
    full_name      = fetch(params, "full_name")
    amount         = fetch(params, "amount")
    monthly_income = fetch(params, "monthly_income")

    # Ojo: el documento puede venir como:
    # - "document" => %{"dni" => "...", ...}
    # - "document_value" => "BNCMRC80A01F205Y"
    raw_document =
      fetch(params, "document") ||
        fetch(params, "document_value")

    # Debug opcional:
    IO.inspect({country, full_name, raw_document, amount, monthly_income},
      label: "raw fields in create_application"
    )

    # Si de verdad faltan país o documento → payload inválido
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

      # Construimos el mapa de documento:
      doc_map =
        cond do
          is_map(raw_document) ->
            # Ya viene estructurado, lo usamos tal cual
            raw_document

          is_binary(raw_document) ->
            # Es un string plano, lo normalizamos según país
            Normalizer.build_document_map(normalized_country, raw_document)

          true ->
            # Cualquier otra cosa rara, intentamos string
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
           :ok <- policy.validate_document(attrs.document),
           {:ok, bank_profile} <- Bank.fetch_profile(attrs.country, attrs),
           :ok <- policy.business_rules(attrs, bank_profile),
           {:ok, app} <- persist_and_enqueue(attrs, bank_profile, policy) do
        {:ok, app}
      else
        {:error, reason} ->
          {:error, reason}

        {:error, type, reason} ->
          {:error, {type, reason}}

        other ->
          {:error, {:unexpected_error, other}}
      end
    end
  end

  def create_application(_), do: {:error, :invalid_payload}

  # =====================
  # Helpers de lectura
  # =====================

  # Lee clave como string o atom; si no existe, devuelve nil
  defp fetch(params, key) do
    Map.get(params, key) ||
      Map.get(params, String.to_atom(key))
  rescue
    ArgumentError ->
      Map.get(params, key)
  end

  # =====================
  # Persistencia + Oban
  # =====================

  @spec persist_and_enqueue(map(), map(), module()) ::
        {:ok, Application.t()} | {:error, any()}
defp persist_and_enqueue(attrs, bank_profile, policy_module) do
  initial_status = policy_module.next_status_on_creation(attrs, bank_profile)

  changes =
    attrs
    |> Map.take([:country, :full_name, :document, :amount, :monthly_income])
    |> Map.put(:status, initial_status)
    |> Map.put(:bank_profile, bank_profile)

  %Application{}
  |> Application.changeset(changes)
  |> Repo.insert()
  |> case do
    {:ok, app} ->
      case enqueue_risk_job(app) do
        :ok -> {:ok, app}
        {:error, reason} -> {:error, {:job_enqueue_failed, reason}}
      end

    {:error, changeset} ->
      {:error, {:invalid_changeset, changeset}}
  end
end

  defp enqueue_risk_job(%Application{id: id}) do
    %{application_id: id}
    |> BravoMultipais.Workers.EvaluateRisk.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
