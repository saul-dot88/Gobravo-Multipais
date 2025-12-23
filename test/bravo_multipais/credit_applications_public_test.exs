defmodule BravoMultipais.CreditApplicationsPublicTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias BravoMultipais.CreditApplications
  alias BravoMultipais.CreditApplications.Application

  describe "to_public/1" do
    test "expone los campos básicos y sanitiza bank_profile" do
      app = %Application{
        id: "app-123",
        country: "ES",
        full_name: "Juan Tester",
        status: "PENDING_RISK",
        risk_score: 720,
        amount: Decimal.new("5000.00"),
        monthly_income: Decimal.new("2000.00"),
        bank_profile: %{
          "external_id" => "bank-abc",
          "total_debt" => 1000,
          "avg_balance" => 2500,
          "currency" => "EUR",
          # campo extra que NO queremos exponer
          "raw_json" => %{"foo" => "bar"}
        },
        # el tipo aquí no importa mucho mientras sea algo razonable;
        # si tu esquema usa :naive_datetime, puedes ajustar este valor
        inserted_at: ~U[2025-01-01 00:00:00Z]
      }

      public = CreditApplications.to_public(app)

      assert %{
               id: "app-123",
               country: "ES",
               full_name: "Juan Tester",
               status: "PENDING_RISK",
               risk_score: 720,
               amount: amount,
               monthly_income: income,
               inserted_at: inserted_at,
               bank_profile: bank_profile
             } = public

      # Tipos de amount / monthly_income (ajusta si en tu esquema son integer/float)
      assert amount == Decimal.new("5000.00")
      assert income == Decimal.new("2000.00")

      assert inserted_at == ~U[2025-01-01 00:00:00Z]

      # bank_profile viene recortado sólo a los campos permitidos
      assert bank_profile == %{
               "external_id" => "bank-abc",
               "total_debt" => 1000,
               "avg_balance" => 2500,
               "currency" => "EUR"
             }

      refute Map.has_key?(bank_profile, "raw_json")
    end

    test "cuando no hay bank_profile, expone bank_profile = nil" do
      app = %Application{
        id: "app-456",
        country: "IT",
        full_name: "Mario Rossi",
        status: "CREATED",
        risk_score: nil,
        amount: Decimal.new("1000.00"),
        monthly_income: Decimal.new("1500.00"),
        bank_profile: nil,
        inserted_at: ~U[2025-01-02 00:00:00Z]
      }

      public = CreditApplications.to_public(app)

      assert public.bank_profile == nil
      assert public.id == "app-456"
      assert public.country == "IT"
      assert public.full_name == "Mario Rossi"
      assert public.status == "CREATED"
    end
  end
end
