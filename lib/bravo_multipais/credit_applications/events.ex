defmodule BravoMultipais.CreditApplications.Events do
  @moduledoc """
  API para registrar y consultar eventos (audit trail) de una solicitud.
  """

  import Ecto.Query, only: [from: 2]

  alias BravoMultipais.Repo
  alias BravoMultipais.CreditApplications.Event

  @default_limit 20

  @type list_opts :: [
          limit: pos_integer(),
          order: :asc | :desc
        ]

  @doc """
  Lista eventos para una solicitud.

  Opciones:
    - limit: cantidad máxima (default #{@default_limit})
    - order: :asc o :desc (default :desc)
  """
  @spec list_for_application(Ecto.UUID.t(), list_opts()) :: [Event.t()]
  def list_for_application(application_id, opts \\ [])
      when is_binary(application_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, @default_limit)
    order = Keyword.get(opts, :order, :desc)

    order_by_expr =
      case order do
        :asc -> [asc: :inserted_at]
        _ -> [desc: :inserted_at]
      end

    from(e in Event,
      where: e.application_id == ^application_id,
      order_by: ^order_by_expr,
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Registra un evento (versión no bang).
  """
  @spec record(Ecto.UUID.t(), String.t(), map(), keyword()) ::
          {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def record(application_id, event_type, payload \\ %{}, opts \\ [])
      when is_binary(application_id) and is_binary(event_type) and is_map(payload) do
    source = Keyword.get(opts, :source, "system")

    %Event{}
    |> Event.changeset(%{
      application_id: application_id,
      event_type: event_type,
      source: source,
      payload: payload
    })
    |> Repo.insert()
  end

  @doc """
  Registra un evento y revienta si falla (útil en flows donde NO quieres silencios).
  """
  @spec record!(Ecto.UUID.t(), String.t(), map(), keyword()) :: Event.t()
  def record!(application_id, event_type, payload \\ %{}, opts \\ []) do
    case record(application_id, event_type, payload, opts) do
      {:ok, ev} -> ev
      {:error, cs} -> raise Ecto.InvalidChangesetError, action: :insert, changeset: cs
    end
  end

  # ---- catálogo sugerido de event_types (opcional) ----
  def event_types do
    ~w(
      created
      risk_enqueued
      risk_evaluated
      webhook_enqueued
      webhook_sending
      webhook_sent
      webhook_failed
      webhook_discarded
      webhook_enqueue_failed
    )
  end
end
