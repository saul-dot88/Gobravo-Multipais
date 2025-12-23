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
    bank_profile: nil,
    risk_score: nil
  }

  defp insert_pending_application(attrs \\ %{}) do
    params = Map.merge(@valid_attrs, attrs)

    %Application{}
    |> Application.changeset(params)
    |> Repo.insert!()
  end

  test "perform/1 actualiza risk_score, status y bank_profile" do
    app = insert_pending_application()
    job = %Job{args: %{"application_id" => app.id}}

    assert :ok = EvaluateRisk.perform(job)

    updated = Repo.get!(Application, app.id)

    # risk_score se calculó
    assert is_integer(updated.risk_score)
    assert updated.risk_score > 0

    # bank_profile se generó y tiene info coherente
    assert is_map(updated.bank_profile)
    assert is_integer(updated.bank_profile["score"])
    assert updated.bank_profile["score"] > 0

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
    assert event in ["updated", "status_changed"]
  end

  test "perform/1 hace no-op si la aplicación no existe" do
    job = %Oban.Job{args: %{"application_id" => Ecto.UUID.generate()}}

    assert :ok = EvaluateRisk.perform(job)
  end
end
