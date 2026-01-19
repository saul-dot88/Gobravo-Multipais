defmodule BravoMultipais.CreditApplications.Event do
  @moduledoc """
  Audit trail / timeline real para solicitudes.

  Guarda eventos de dominio e integración relacionados a una credit_application.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "credit_application_events" do
    field :event_type, :string
    field :source, :string, default: "system"
    field :payload, :map, default: %{}

    belongs_to :application, BravoMultipais.CreditApplications.Application,
      foreign_key: :application_id

    timestamps(type: :naive_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @required ~w(application_id event_type source)a
  @optional ~w(payload)a

  def changeset(event, attrs) do
    event
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_length(:event_type, min: 2, max: 100)
    |> validate_length(:source, min: 2, max: 50)
  end
end
