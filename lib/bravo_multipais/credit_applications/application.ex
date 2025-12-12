defmodule BravoMultipais.CreditApplications.Application do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @countries ~w(ES IT PT)
  @statuses ~w(CREATED PENDING_RISK UNDER_REVIEW APPROVED REJECTED)

  schema "credit_applications" do
    field :country, :string
    field :full_name, :string
    field :document, :map
    field :amount, :decimal
    field :monthly_income, :decimal
    field :bank_profile, :map
    field :status, :string
    field :risk_score, :integer
    field :external_reference, :string

    timestamps()
  end

  @doc """
  Changeset para crear una solicitud.
  Aquí solo validamos lo básico. Las reglas por país se aplican más arriba,
  en la capa de dominio (Policies).
  """
  def create_changeset(%__MODULE__{} = app, attrs) do
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
    |> validate_required([:country, :full_name, :document, :amount, :monthly_income, :status])
    |> validate_inclusion(:country, @countries)
    |> validate_inclusion(:status, @statuses)
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
