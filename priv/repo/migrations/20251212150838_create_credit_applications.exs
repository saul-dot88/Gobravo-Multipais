defmodule BravoMultipais.Repo.Migrations.CreateCreditApplications do
  use Ecto.Migration

  def change do
    create table(:credit_applications, primary_key: false) do
      add :id, :uuid, primary_key: true
      # País: ES, IT, PT
      add :country, :string, null: false

      # Datos del solicitante
      add :full_name, :string, null: false
      # Documento (DNI/NIF/NIE para ES, NIF para PT, Codice Fiscale para IT) en JSON
      add :document, :map, null: false

      # Monto solicitado e ingreso mensual
      add :amount, :decimal, null: false
      add :monthly_income, :decimal, null: false

      # Fecha de creación de la solicitud (usaremos inserted_at, pero la dejamos explícita si quieres)
      # add :requested_at, :utc_datetime_usec, null: false, default: fragment("now()")

      # Información bancaria normalizada por país (vendrá del proveedor)
      add :bank_profile, :map

      # Estado del flujo: CREATED, PENDING_RISK, UNDER_REVIEW, APPROVED, REJECTED
      add :status, :string, null: false

      # Información extra para scoring
      add :risk_score, :integer
      add :external_reference, :string

      timestamps()
    end

    create index(:credit_applications, [:country])
    create index(:credit_applications, [:status])
    create index(:credit_applications, [:country, :status])
  end
end
