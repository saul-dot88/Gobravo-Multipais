defmodule BravoMultipais.CreditApplications.Commands do
  @moduledoc """
  Commands para crear solicitudes de crédito multipaís.

  Orquesta:
  - Normalización de parámetros de entrada
  - Consulta del perfil bancario
  - Aplicación de políticas por país (validación + reglas de negocio)
  - Persistencia de la solicitud
  - Encolado del worker de riesgo en Oban
  """

  alias BravoMultipais.{Repo, Bank, Policies}
  alias BravoMultipais.CreditApplications.Application
  alias BravoMultipais.Workers.EvaluateRisk
  alias Ecto.Changeset

  @spec create_application(map()) ::
          {:ok, Application.t()}
          | {:error, Changeset.t()}
          | {:error, {:business_rules_failed, term()}}
          | {:error, term()}
  def create_application(params) when is_map(params) do
    country = params["country"] || params[:country]

    with {:ok, app_attrs} <- build_attrs(params),
         {:ok, bank_profile} <- Bank.fetch_profile(country, app_attrs),
         policy <- Policies.policy_for(country),
         :ok <- policy.validate_document(app_attrs.document),
         :ok <- policy.business_rules(app_attrs, bank_profile),
         initial_status <- policy.next_status_on_creation(app_attrs, bank_profile),
         {:ok, %Application{} = app} <- create_and_enqueue(app_attrs, initial_status) do
      {:ok, app}
    else
      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, {:business_rules_failed, _} = err} ->
        {:error, err}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Normaliza/arma el mapa base con el que trabajan las Policies y el schema
  defp build_attrs(params) do
    country        = params["country"] || params[:country]
    full_name      = params["full_name"] || params[:full_name]
    amount         = params["amount"] || params[:amount]
    monthly_income = params["monthly_income"] || params[:monthly_income]
    document_value = params["document_value"] || params[:document_value]

    document =
      BravoMultipais.Bank.Normalizer.build_document_map(country, document_value)

    attrs = %{
      country: country,
      full_name: full_name,
      amount: amount,
      monthly_income: monthly_income,
      document: document
    }

    {:ok, attrs}
  rescue
    e ->
      {:error, {:bad_request, e}}
  end

  # Inserta la solicitud con el estado inicial y encola el worker de riesgo
  defp create_and_enqueue(app_attrs, initial_status) do
    attrs_with_status =
      app_attrs
      |> Map.put(:status, initial_status)

    %Application{}
    |> Application.changeset(attrs_with_status)
    |> Repo.insert()
    |> case do
      {:ok, %Application{} = app} ->
        # Encolamos el job en la cola :risk
        %{application_id: app.id}
        |> EvaluateRisk.new(queue: :risk)
        |> Oban.insert()

        {:ok, app}

      error ->
        error
    end
  end
end
