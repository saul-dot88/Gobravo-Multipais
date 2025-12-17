defmodule BravoMultipais.Workers.WebhookNotifier do
  @moduledoc """
  Worker Oban para enviar notificaciones a un webhook externo
  cuando cambia el estado de una solicitud.

  Lo usamos después de que `EvaluateRisk` calcule el score y actualice
  el estado de la `Application`.
  """

  use Oban.Worker,
    queue: :webhook,
    max_attempts: 5

  alias BravoMultipais.{Repo}
  alias BravoMultipais.CreditApplications.Application

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"application_id" => id}}) do
    app = Repo.get!(Application, id)

    payload = %{
      application_id: app.id,
      status: app.status,
      risk_score: app.risk_score,
      country: app.country,
      full_name: app.full_name,
      event: "application.status_changed",
      occurred_at: DateTime.utc_now()
    }

    body = Jason.encode!(payload)
    url = webhook_url()

    headers = [
      {"content-type", "application/json"},
      # “firma” fake para que se vea realista
      {"x-bravo-signature", fake_signature(body)}
    ]

    Logger.info("Enviando webhook a #{url}", application_id: app.id)

    case Finch.build(:post, url, headers, body)
         |> Finch.request(BravoMultipais.Finch) do
      {:ok, %Finch.Response{status: status} = resp} when status in 200..299 ->
        Logger.info("Webhook enviado correctamente",
          application_id: app.id,
          status: status
        )

        :ok

      {:ok, %Finch.Response{status: status, body: resp_body}} ->
        Logger.warning("Webhook respondió con error",
          application_id: app.id,
          status: status,
          body: resp_body
        )

        {:error, :remote_error}

      {:error, reason} ->
        Logger.error("Error HTTP al llamar webhook",
          application_id: app.id,
          reason: inspect(reason)
        )

        {:error, :http_error}
    end
  end

  @doc """
  Helper para encolar el job desde otros módulos.
  """
  def enqueue(application_id) do
    %{"application_id" => application_id}
    |> new()
    |> Oban.insert()
  end

  defp webhook_url do
    Application.get_env(
      :bravo_multipais,
      :webhook_url,
      "http://localhost:4001/webhooks/applications"
    )
  end

  defp fake_signature(body) do
    :crypto.hash(:sha256, "super-secret" <> body)
    |> Base.encode16(case: :lower)
  end
end
