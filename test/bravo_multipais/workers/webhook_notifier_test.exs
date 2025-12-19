# test/bravo_multipais/workers/webhook_notifier_test.exs
defmodule BravoMultipais.Workers.WebhookNotifierTest do
  use BravoMultipais.DataCase, async: true

  alias BravoMultipais.Workers.WebhookNotifier
  alias BravoMultipais.CreditApplications.Application
  alias BravoMultipais.Repo

  describe "enqueue/1" do
    test "devuelve :ok para un application_id válido" do
      app = insert_application!()

      # No nos acoplamos a la tabla oban_jobs ni al engine,
      # sólo verificamos que el contrato público se cumple.
      assert :ok = WebhookNotifier.enqueue(app.id)
    end
  end

  describe "perform/1" do
    test "en entorno test sólo lee la app y devuelve :ok" do
      app =
        insert_application!(%{
          status: "APPROVED",
          risk_score: 750
        })

      job = %Oban.Job{args: %{"application_id" => app.id}}

      assert :ok = WebhookNotifier.perform(job)

      # Verificamos que la app sigue existiendo y con los mismos datos
      reloaded = Repo.get!(Application, app.id)
      assert reloaded.id == app.id
      assert reloaded.status == "APPROVED"
      assert reloaded.risk_score == 750
    end

    test "levanta si la aplicación no existe" do
      job = %Oban.Job{args: %{"application_id" => Ecto.UUID.generate()}}

      assert_raise Ecto.NoResultsError, fn ->
        WebhookNotifier.perform(job)
      end
    end
  end

  # --- helper privado para crear aplicaciones de prueba ---

  defp insert_application!(overrides \\ %{}) do
    base_attrs = %{
      country: "ES",
      full_name: "Juan Test",
      document: %{"dni" => "12345678Z", "raw" => "12345678Z"},
      amount: Decimal.new("5000"),
      monthly_income: Decimal.new("2000"),
      status: "PENDING_RISK"
    }

    attrs = Map.merge(base_attrs, overrides)

    %Application{}
    |> Application.changeset(attrs)
    |> Repo.insert!()
  end
end
