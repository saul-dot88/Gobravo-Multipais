defmodule BravoMultipaisWeb.FallbackController do
  use BravoMultipaisWeb, :controller

  alias Ecto.Changeset

  # 422 para errores de changeset (validación de datos)
  def call(conn, {:error, %Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: BravoMultipaisWeb.ErrorJSON)
    |> render(:changeset, changeset: changeset)
  end

  # 422 para reglas de negocio
  def call(conn, {:error, {:business_rules_failed, reason}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(business_error_payload(reason))
  end

  # 404 cuando no se encuentra la solicitud
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{
      error: "not_found",
      message: "Credit application not found"
    })
  end

  # 400 para request mal formado
  def call(conn, {:error, :bad_request}) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "bad_request",
      message: "Invalid request payload"
    })
  end

  # Catch-all (por si algo raro se va como {:error, other})
  def call(conn, {:error, other}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{
      error: "internal_error",
      detail: inspect(other)
    })
  end

  # ---- helpers de modelo de error de negocio ----

  defp business_error_payload(:invalid_income) do
    business_error_payload_base(
      "invalid_income",
      "Monthly income is invalid for this product/country"
    )
  end

  defp business_error_payload({:invalid_income, :below_minimum_income}) do
    business_error_payload_base(
      "invalid_income_below_minimum",
      "Monthly income is below the minimum allowed"
    )
  end

  defp business_error_payload(:invalid_amount) do
    business_error_payload_base(
      "invalid_amount",
      "Requested amount must be greater than zero"
    )
  end

  defp business_error_payload(:amount_too_high_relative_to_income) do
    business_error_payload_base(
      "amount_too_high_relative_to_income",
      "Requested amount is too high relative to customer income"
    )
  end

  defp business_error_payload(:debt_to_income_too_high) do
    business_error_payload_base(
      "debt_to_income_too_high",
      "Debt-to-income ratio is higher than the allowed threshold"
    )
  end

  defp business_error_payload(:invalid_spanish_document) do
    business_error_payload_base(
      "invalid_document_es",
      "Invalid Spanish document (DNI / NIF / NIE)"
    )
  end

  defp business_error_payload(:invalid_codice_fiscale) do
    business_error_payload_base(
      "invalid_document_it",
      "Invalid Italian codice fiscale"
    )
  end

  defp business_error_payload(:invalid_nif) do
    business_error_payload_base(
      "invalid_document_pt",
      "Invalid Portuguese NIF"
    )
  end

  defp business_error_payload(other) do
    business_error_payload_base(
      to_string(other),
      "Business rule violation"
    )
  end

  defp business_error_payload_base(code, message) do
    %{
      error: "business_rules_failed",
      code: code,
      message: message
    }
  end
end
