defmodule BravoMultipais.CreditApplications.Commands do
  @moduledoc """
  Casos de uso para crear y actualizar solicitudes de crédito.
  Aquí orquestamos políticas por país, proveedor bancario y jobs async.
  """

  alias BravoMultipais.Repo
  alias BravoMultipais.CreditApplications.Application
  alias BravoMultipais.Policies.Factory, as: PolicyFactory
  alias BravoMultipais.Bank.Factory, as: BankFactory
  alias BravoMultipais.Bank.Normalizer
  alias BravoMultipais.Jobs.EvaluateRisk
  alias Oban

  @doc """
  Crea una nueva solicitud de crédito multipaís.

  Flujo:
    1. Validar país y datos básicos.
    2. Aplicar validación de documento según país.
    3. Llamar proveedor bancario para obtener perfil financiero.
    4. Normalizar perfil bancario.
    5. Aplicar reglas de negocio por país.
    6. Determinar estado inicial.
    7. Guardar en DB.
    8. Encolar job de evaluación de riesgo.
  """
  def create_application(attrs) when is_map(attrs) do
    Repo.transaction(fn ->
      country = Map.fetch!(attrs, "country")

      policy = PolicyFactory.policy_for(country)
      bank_provider = BankFactory.provider_for(country)

      # 1) Validar documento según país (DNI ES, CF IT, NIF PT, etc.)
      document = Map.fetch!(attrs, "document")

      case policy.validate_document(document) do
        :ok ->
          :ok

        {:error, reason} ->
          Repo.rollback({:validation_error, :invalid_document, reason})
      end

      # 2) Obtener información bancaria simulada para el país
      case bank_provider.fetch_info(document) do
        {:ok, raw_bank_data} ->
          bank_profile = Normalizer.normalize(country, raw_bank_data)

          # 3) Aplicar reglas de negocio por país (monto, ingreso, deuda, etc.)
          #    Para eso armamos una estructura transitoria con los datos de la solicitud
          #    (sin guardar todavía).
          app_params = %{
            country: country,
            full_name: Map.fetch!(attrs, "full_name"),
            document: document,
            amount: Map.fetch!(attrs, "amount"),
            monthly_income: Map.fetch!(attrs, "monthly_income"),
            bank_profile: bank_profile
          }

          case policy.business_rules(app_params, bank_profile) do
            :ok ->
              # 4) Determinar estado inicial según país y perfil bancario
              initial_status = policy.next_status_on_creation(app_params, bank_profile)

              # 5) Persistimos en DB
              create_and_enqueue(app_params, initial_status)

            {:error, reason} ->
              Repo.rollback({:validation_error, :business_rules_failed, reason})
          end

        {:error, reason} ->
          Repo.rollback({:integration_error, :bank_provider_failed, reason})
      end
    end)
    |> case do
      {:ok, app} ->
        {:ok, app}

      {:error, {:validation_error, type, detail}} ->
        {:error, {:validation_error, type, detail}}

      {:error, {:integration_error, type, detail}} ->
        {:error, {:integration_error, type, detail}}

      {:error, other} ->
        {:error, other}
    end
  end

  defp create_and_enqueue(app_params, initial_status) do
    params_for_db =
      app_params
      |> Map.put(:status, initial_status)

    %Application{}
    |> Application.create_changeset(params_for_db)
    |> Repo.insert()
    |> case do
      {:ok, app} ->
        # Encolamos job de evaluación de riesgo
        %{application_id: app.id}
        |> EvaluateRisk.new()
        |> Oban.insert()

        app

      {:error, changeset} ->
        # rollback de la transacción
        Repo.rollback({:changeset_error, changeset})
    end
  end
end
