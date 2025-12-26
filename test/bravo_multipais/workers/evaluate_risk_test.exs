defmodule BravoMultipais.Workers.EvaluateRiskTest do
  use BravoMultipais.DataCase, async: true

  alias BravoMultipais.CreditApplications.Application
  alias BravoMultipais.Repo
  alias BravoMultipais.Workers.EvaluateRisk
  alias Oban.Job

  @valid_attrs %{
    country: "ES",
    full_name: "Juan Pérez",
    document: %{"dni" => "12345678Z"},
    amount: Decimal.new("5000"),
    monthly_income: Decimal.new("2000"),
    status: "PENDING_RISK",
    # en el flujo real viene del servicio externo; aquí sólo
    # lo usamos para comprobar que el worker NO lo toca
    bank_profile: %{"score" => 650, "country" => "ES"},
    risk_score: nil
  }

  defp insert_pending_application(attrs \\ %{}) do
    params = Map.merge(@valid_attrs, attrs)

    %Application{}
    |> Application.changeset(params)
    |> Repo.insert!()
  end

  test "perform/1 actualiza risk_score y status, sin tocar bank_profile" do
    app = insert_pending_application()
    job = %Job{args: %{"application_id" => app.id}}

    assert :ok = EvaluateRisk.perform(job)

    updated = Repo.get!(Application, app.id)

    # risk_score se calculó
    assert is_integer(updated.risk_score)
    assert updated.risk_score > 0

    # bank_profile NO es responsabilidad del worker generarlo;
    # sólo debe respetar lo que ya hubiera
    assert updated.bank_profile == app.bank_profile

    # el status salió de PENDING_RISK a algún estado “final”
    refute updated.status == "PENDING_RISK"
    assert updated.status in ["APPROVED", "REJECTED", "UNDER_REVIEW"]
  end

  test "perform/1 publica un evento en el tópico \"applications\"" do
    app = insert_pending_application()

    Phoenix.PubSub.subscribe(BravoMultipais.PubSub, "applications")

    job = %Job{args: %{"application_id" => app.id}}

    assert :ok = EvaluateRisk.perform(job)

    assert_receive %Phoenix.Socket.Broadcast{
                     topic: "applications",
                     event: event,
                     payload: %{id: received_id}
                   },
                   1_000

    assert received_id == app.id
    # si en el futuro cambias el evento, puedes ajustar aquí
    assert event in ["updated", "status_changed"]
  end

  test "perform/1 hace no-op (discard) si la aplicación no existe" do
    job = %Job{args: %{"application_id" => Ecto.UUID.generate()}}

    # ahora el worker descarta el job para que Oban no reintente indefinidamente
    assert :discard = EvaluateRisk.perform(job)
  end
end
