defmodule BravoMultipais.Repo.Migrations.CreateCreditApplicationEvents do
  use Ecto.Migration

  def change do
    create table(:credit_application_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :application_id,
          references(:credit_applications, type: :binary_id, on_delete: :delete_all),
          null: false

      add :event_type, :string, null: false
      add :source, :string, null: false, default: "system"

      # payload flexible (score, status, http_status, url, reason, etc.)
      add :payload, :map, null: false, default: %{}

      timestamps(type: :naive_datetime_usec)
    end

    create index(:credit_application_events, [:application_id])
    create index(:credit_application_events, [:application_id, :inserted_at])
    create index(:credit_application_events, [:event_type])
  end
end
