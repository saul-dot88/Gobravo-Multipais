defmodule BravoMultipais.CreditApplicationsTest do
  @moduledoc false

  use BravoMultipais.DataCase, async: true

  alias BravoMultipais.CreditApplications
  alias BravoMultipais.CreditApplications.Application
  alias BravoMultipais.Repo

  describe "list_applications_public/1" do
    test "devuelve todas las aplicaciones en forma pública sin filtros" do
      app1 = insert_application!(%{country: "ES", status: "APPROVED"})
      app2 = insert_application!(%{country: "IT", status: "REJECTED"})

      result = CreditApplications.list_applications_public(%{})

      ids = Enum.map(result, & &1.id) |> Enum.sort()

      assert ids == Enum.sort([app1.id, app2.id])

      # El view público debe exponer, al menos, estos campos
      assert Enum.all?(result, fn m ->
               is_binary(m.id) and
                 is_binary(m.country) and
                 is_binary(m.full_name) and
                 is_binary(m.status)
             end)
    end

    test "filtra por country (string key como viene del controller)" do
      app_es = insert_application!(%{country: "ES", status: "APPROVED"})
      _app_it = insert_application!(%{country: "IT", status: "APPROVED"})

      result = CreditApplications.list_applications_public(%{"country" => "ES"})

      assert Enum.map(result, & &1.id) == [app_es.id]
      assert Enum.all?(result, &(&1.country == "ES"))
    end

    test "filtra por status" do
      app_approved = insert_application!(%{country: "ES", status: "APPROVED"})
      _app_rejected = insert_application!(%{country: "ES", status: "REJECTED"})

      result = CreditApplications.list_applications_public(%{"status" => "APPROVED"})

      assert Enum.map(result, & &1.id) == [app_approved.id]
      assert Enum.all?(result, &(&1.status == "APPROVED"))
    end
  end

  describe "get_application_public/1" do
    test "devuelve el view público cuando el id existe" do
      app = insert_application!(%{country: "ES", status: "APPROVED"})

      public = CreditApplications.get_application_public(app.id)

      refute is_nil(public)

      # public es un map con keys de átomo (:id, :country, etc.)
      assert public.id == app.id
      assert public.country == "ES"
      assert public.status == "APPROVED"

      # Document sale ya en la forma pública
      assert public.document == app.document
    end

    test "devuelve nil cuando el id no existe" do
      assert CreditApplications.get_application_public(Ecto.UUID.generate()) == nil
    end
  end

  # --- helper privado para crear aplicaciones sin pasar por Commands/Oban ---

  defp insert_application!(overrides \\ %{}) do
    base_attrs = %{
      country: "ES",
      full_name: "Test User",
      document: %{"dni" => "12345678Z"},
      amount: Decimal.new("5000"),
      monthly_income: Decimal.new("2000"),
      risk_score: nil,
      bank_profile: nil,
      status: "PENDING_RISK",
      external_reference: nil
      # inserted_at / updated_at los rellena Ecto
    }

    attrs = Map.merge(base_attrs, overrides)

    %Application{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!()
  end
end
