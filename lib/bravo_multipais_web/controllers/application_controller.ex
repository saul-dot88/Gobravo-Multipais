defmodule BravoMultipaisWeb.ApplicationController do
  use BravoMultipaisWeb, :controller
  use OpenApiSpex.ControllerSpecs


  alias BravoMultipais.CreditApplications
  alias BravoMultipaisWeb.ApiAuth

  alias BravoMultipaisWeb.Schemas.{
    CreditApplicationCreateRequest,
    CreditApplicationResponse,
    Error
  }

  alias OpenApiSpex.Schema


  plug :require_backoffice when action in [:index, :show]
  plug :require_creator when action in [:create]

  tags(["Applications"])

  operation(
    :index,
    summary: "List credit applications",
    description: "Lista de solicitudes de crédito (demo, sin paginación).",
    responses: %{
      200 =>
        {"List of applications", "application/json",
         %Schema{
           type: :array,
           items: CreditApplicationResponse
         }}
    }
  )

  # GET /api/applications
  def index(conn, params) do
    apps = CreditApplications.list_applications_public(params)
    json(conn, %{data: apps})
  end

  operation(:create,
    summary: "Create credit application",
    description: "Crea una nueva solicitud de crédito multipaís.",
    request_body:
      {"Application payload", "application/json", CreditApplicationCreateRequest, required: true},
    responses: %{
      201 => {"Application created", "application/json", CreditApplicationResponse},
      400 => {"Bad request", "application/json", Error}
    }
  )

  # GET /api/applications/:id
  def show(conn, %{"id" => id}) do
    case BravoMultipais.CreditApplications.get_application_public(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{"error" => "application_not_found"})

      public_app ->
        # JSON plano, con "id", "country", "document" (string), etc.
        json(conn, public_app)
    end
  end

  operation(:show,
    summary: "Get credit application by ID",
    parameters: [
      id: [in: :path, description: "Application UUID", type: :string, example: "uuid-here"]
    ],
    responses: %{
      200 => {"Application", "application/json", CreditApplicationResponse},
      404 => {"Not found", "application/json", Error}
    }
  )

  # POST /api/applications
  def create(conn, params) do
    params = normalize_document(params)

    case CreditApplications.create_application(params) do
      {:ok, app} ->
        conn
        |> put_status(:created)
        |> json(%{data: CreditApplications.to_public(app)})

      {:error, {:policy_error, reason}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "policy_error", reason: inspect(reason)})

      {:error, {:invalid_changeset, %Ecto.Changeset{} = changeset}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_error", details: changeset_errors(changeset)})

      {:error, :invalid_payload} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_payload"})

      {:error, other} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "unexpected_error", reason: inspect(other)})
    end
  end

  # --- normalización de documento ---

  defp normalize_document(%{"document" => %{} = _doc} = params), do: params

  defp normalize_document(%{"country" => country, "document_value" => value} = params) do
    document =
      case String.upcase(country) do
        "IT" -> %{"codice_fiscale" => value}
        "ES" -> %{"dni" => value}
        "PT" -> %{"nif" => value}
        _ -> %{"raw" => value}
      end

    params
    |> Map.put("document", document)
    |> Map.delete("document_value")
  end

  defp normalize_document(params), do: params

  # --- plugs privados ---

  defp require_backoffice(conn, _opts), do: ApiAuth.require_backoffice(conn)

  defp require_creator(conn, _opts) do
    ApiAuth.require_role(conn, ["backoffice", "external"])
  end

  # --- helpers de error ---

  defp changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
