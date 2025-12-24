defmodule BravoMultipais.Workers.EvaluateRisk do
  @moduledoc """
  Worker Oban que simula la evaluación de riesgo de una solicitud de crédito,
  actualiza el `risk_score` y publica cambios en PubSub/Kafka interno.
  """

  use Oban.Worker,
    queue: :risk,
    max_attempts: 3

  alias BravoMultipais.CreditApplications.Application
  alias BravoMultipais.BankCache
  alias BravoMultipais.LogSanitizer
  alias BravoMultipais.Repo
  alias BravoMultipaisWeb.Endpoint

  require Logger

  @topic "applications"

  @doc """
  Encola una evaluación de riesgo para la aplicación dada.

  Retorna:
    * :ok
    * {:error, reason}
  """
  @spec enqueue(Ecto.UUID.t()) :: :ok | {:error, term()}
  def enqueue(application_id) when is_binary(application_id) do
    %{"application_id" => application_id}
    |> __MODULE__.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"application_id" => id}}) do
    case Repo.get(Application, id) do
      nil ->
        # Si la solicitud ya no existe, consideramos el job consumido
        :ok

      %Application{} = app ->
        {risk_score, status, bank_profile} = evaluate(app)

        changeset =
          Application.changeset(app, %{
            risk_score: risk_score,
            status: status,
            bank_profile: bank_profile
          })

        case Repo.update(changeset) do
          {:ok, updated_app} ->
            # Notificamos al LiveView para auto-refresh
            Endpoint.broadcast(@topic, "status_changed", %{
              id: updated_app.id,
              status: updated_app.status,
              risk_score: updated_app.risk_score
            })

            Logger.info("Risk evaluation completed",
              application_id: updated_app.id,
              country: updated_app.country,
              risk_score: updated_app.risk_score,
              document_masked: LogSanitizer.mask_document(updated_app.document)
            )

            :ok

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  # ─────────────────────────────
  # Lógica "fake" de evaluación
  # ─────────────────────────────

  defp evaluate(%Application{} = app) do
    ratio =
      with %Decimal{} = amount <- app.amount,
           %Decimal{} = income <- app.monthly_income,
           true <- Decimal.cmp(income, 0) == :gt do
        Decimal.div(amount, income)
      else
        _ -> Decimal.new("99")
      end

    base_score =
      cond do
        Decimal.cmp(ratio, Decimal.new("0.5")) == :lt -> 780
        Decimal.cmp(ratio, Decimal.new("1.0")) == :lt -> 720
        Decimal.cmp(ratio, Decimal.new("1.5")) == :lt -> 660
        true -> 620
      end

    status =
      if base_score >= 660 do
        "APPROVED"
      else
        "REJECTED"
      end

    bank_profile = BankCache.fetch_profile(app)

    {base_score, status, bank_profile}
  end
end
