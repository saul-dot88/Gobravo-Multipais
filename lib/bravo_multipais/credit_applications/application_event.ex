defmodule BravoMultipais.CreditApplications.ApplicationEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "application_events" do
    field :type, :string
    field :source, :string, default: "system"
    field :payload, :map

    belongs_to :application, BravoMultipais.CreditApplications.Application,
      foreign_key: :application_id

    timestamps(type: :naive_datetime_usec)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:application_id, :type, :source, :payload])
    |> validate_required([:application_id, :type, :source])
  end
end
