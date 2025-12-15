defmodule BravoMultipaisWeb.MockWebhookController do
  use BravoMultipaisWeb, :controller

  require Logger

  @doc """
  Endpoint que simula un sistema externo recibiendo webhooks.

  - Recibe JSON enviado por `WebhookNotifier`.
  - Loguea lo que llega (para observabilidad).
  - Devuelve 200 OK con un pequeño payload de confirmación.
  """
  def receive(conn, params) do
    Logger.info("Mock webhook recibido",
      event: params["event"],
      application_id: params["application_id"],
      status: params["status"],
      risk_score: params["risk_score"],
      country: params["country"]
    )

    # Aquí podrías simular lógica extra (guardar en otra tabla, disparar otro proceso, etc.)
    # Para el reto basta con confirmar que el “sistema externo” procesó el evento.

    json(conn, %{
      "status" => "ok",
      "processed_by" => "mock_external_system",
      "received_at" => DateTime.utc_now(),
      "echo_event" => params["event"]
    })
  end
end
