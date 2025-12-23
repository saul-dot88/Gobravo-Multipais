defmodule BravoMultipais.CreditApplications.Application do
  @moduledoc """
  Esquema principal de una solicitud de crédito multipaís.

  Modela atributos como país, monto, ingreso mensual, estado,
  `risk_score` y perfil bancario, y sirve de base para el flujo
  de evaluación de riesgo y notificación de webhooks.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @derive {Jason.Encoder,
           only: [
             :id,
             :country,
             :full_name,
             :document,
             :amount,
             :monthly_income,
             :bank_profile,
             :status,
             :risk_score,
             :external_reference,
             :inserted_at,
             :updated_at
           ]}

  schema "credit_applications" do
    field :country, :string
    field :full_name, :string
    field :document, :map

    # Numéricos
    field :amount, :decimal
    field :monthly_income, :decimal
    field :risk_score, :integer

    # Info bancaria agregada
    field :bank_profile, :map

    # Otros metadatos
    field :status, :string
    field :external_reference, :string

    timestamps()
  end

  @doc false
  def changeset(%__MODULE__{} = app, attrs) do
    app
    |> cast(attrs, [
      :country,
      :full_name,
      :document,
      :amount,
      :monthly_income,
      :bank_profile,
      :status,
      :risk_score,
      :external_reference
    ])
    |> validate_required([
      :country,
      :full_name,
      :document,
      :amount,
      :monthly_income,
      :status
    ])
  end

  @doc """
  Changeset para actualizar solo el estado (lo usaremos después para transiciones).
  """
  def status_changeset(%__MODULE__{} = app, new_status) do
    app
    |> change()
    |> put_change(:status, new_status)
    |> validate_inclusion(:status, @statuses)
  end
end
