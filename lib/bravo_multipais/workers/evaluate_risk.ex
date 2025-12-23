defmodule BravoMultipais.Workers.EvaluateRisk do
  @moduledoc """
  Worker Oban que simula la evaluación de riesgo de una solicitud de crédito,
  actualiza el `risk_score` y publica cambios en PubSub/Kafka interno.
  """
  use Oban.Worker,
    queue: :risk,
    max_attempts: 3

  alias BravoMultipais.CreditApplications.Application
  alias BravoMultipais.Repo

  alias BravoMultipais.LogSanitizer
  alias BravoMultipaisWeb.Endpoint

  require Logger

  @topic "applications"

  @doc """
  Encola una evaluación de riesgo para la aplicación dada.

  Retorna:
    * :ok
    * {:error, reason}
  """
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
        # Nada que hacer; puedes registrar log si quieres
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
              application_id: app.id,
              country: app.country,
              risk_score: app.risk_score,
              document_masked: LogSanitizer.mask_document(app.document)
            )

            :ok

          {:error, changeset} ->
            # Oban marcará el job como error, reintento si aplica
            {:error, changeset}
        end
    end
  end

  # ─────────────────────────────
  # Lógica "fake" de evaluación
  # ─────────────────────────────

  defp evaluate(app) do
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

    bank_profile = build_fake_bank_profile(app, base_score)

    {base_score, status, bank_profile}
  end

  defp build_fake_bank_profile(app, score) do
    amount = app.amount || Decimal.new(0)
    income = app.monthly_income || Decimal.new(0)

    total_debt =
      amount
      |> Decimal.mult(Decimal.new("0.8"))
      |> Decimal.to_float()

    avg_balance =
      income
      |> Decimal.mult(Decimal.new("3.5"))
      |> Decimal.to_float()

    %{
      country: app.country,
      currency: "EUR",
      score: score,
      total_debt: total_debt,
      avg_balance: avg_balance,
      external_id: "BANK-#{mask_doc(app.document)}"
    }
  end

  defp mask_doc(%{"dni" => dni}) when is_binary(dni), do: dni
  defp mask_doc(%{"codice_fiscale" => cf}) when is_binary(cf), do: cf
  defp mask_doc(%{"nif" => nif}) when is_binary(nif), do: nif
  defp mask_doc(%{"raw" => raw}) when is_binary(raw), do: raw
  defp mask_doc(_), do: "UNKNOWN"
end
