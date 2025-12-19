defmodule BravoMultipais.CreditApplications.CommandsTest do
  use BravoMultipais.DataCase, async: true

  alias BravoMultipais.CreditApplications.{Commands, Application}
  alias BravoMultipais.Repo

  describe "create_application/1" do
    test "create_application/1 persiste una aplicación con documento normalizado cuando los params son válidos" do
      params = %{
        "country" => "ES",
        "full_name" => "Juan Pérez",
        "amount" => "5000",
        "monthly_income" => "2000",
        "document_value" => "12345678Z"
      }

      assert {:ok, %Application{} = app} = Commands.create_application(params)

      # 👇 Aquí validamos el estado inicial antes de que el worker de riesgo actúe
      assert app.country == "ES"
      assert app.status == "PENDING_RISK"
      assert app.document == %{"dni" => "12345678Z", "raw" => "12345678Z"}
      assert is_nil(app.risk_score)

      # Si quieres seguir validando que se persistió, hazlo sin fijar el status
      app_db = Repo.get!(Application, app.id)
      assert app_db.country == "ES"
      assert app_db.document == %{"dni" => "12345678Z", "raw" => "12345678Z"}
      # 👇 no asertamos el status porque el worker ya lo pudo cambiar
      # assert app_db.status == "PENDING_RISK"
    end

    test "regresa error :invalid_payload cuando falta país o documento" do
      # Falta country
      params_missing_country = %{
        "full_name" => "Test",
        "amount" => "1000",
        "monthly_income" => "1000",
        "document_value" => "123"
      }

      assert {:error, :invalid_payload} =
               Commands.create_application(params_missing_country)

      # Falta document_value/document
      params_missing_doc = %{
        "country" => "ES",
        "full_name" => "Test",
        "amount" => "1000",
        "monthly_income" => "1000"
      }

      assert {:error, :invalid_payload} =
               Commands.create_application(params_missing_doc)
    end

    test "aplica reglas de negocio y falla cuando el ingreso es demasiado bajo" do
      params = %{
        "country" => "ES",
        "full_name" => "Cliente Riesgoso",
        "document_value" => "12345678Z",
        "amount" => "20000",
        # < 600 → ESPolicy.business_rules/2 => {:error, :income_too_low}
        "monthly_income" => "300"
      }

      assert {:error, :income_too_low} = Commands.create_application(params)
    end
  end
end
