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

  defp business_error_payload(reason) do
    {code, message} =
      case reason do
        :invalid_income ->
          {"invalid_income", "Monthly income is invalid for this product/country"}

        {:invalid_income, :below_minimum_income} ->
          {"invalid_income_below_minimum", "Monthly income is below the minimum allowed"}

        :invalid_amount ->
          {"invalid_amount", "Requested amount must be greater than zero"}

        :amount_too_high_relative_to_income ->
          {"amount_too_high_relative_to_income",
           "Requested amount is too high relative to customer income"}

        :debt_to_income_too_high ->
          {"debt_to_income_too_high",
           "Debt-to-income ratio is higher than the allowed threshold"}

        :invalid_spanish_document ->
          {"invalid_document_es", "Invalid Spanish document (DNI / NIF / NIE)"}

        :invalid_codice_fiscale ->
          {"invalid_document_it", "Invalid Italian codice fiscale"}

        :invalid_nif ->
          {"invalid_document_pt", "Invalid Portuguese NIF"}

        other ->
          {to_string(other), "Business rule violation"}
      end

    %{
      error: "business_rules_failed",
      code: code,
      message: message
    }
  end
end
