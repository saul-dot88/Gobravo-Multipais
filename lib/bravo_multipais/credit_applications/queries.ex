defmodule BravoMultipais.CreditApplications.Queries do
  @moduledoc """
  Consultas de solo lectura sobre las solicitudes de crédito.
  """

  import Ecto.Query, only: [from: 2, order_by: 2]

  alias BravoMultipais.Repo
  alias BravoMultipais.CreditApplications.Application

  @spec get_application(Ecto.UUID.t()) :: Application.t() | nil
  def get_application(id), do: Repo.get(Application, id)

  @spec get_application_details(Ecto.UUID.t()) :: Application.t() | nil
  def get_application_details(id), do: get_application(id)

  @spec list_applications(map()) :: list(map())
  def list_applications(params \\ %{}) do
    country = Map.get(params, "country") || Map.get(params, :country)
    status = Map.get(params, "status") || Map.get(params, :status)

    Application
    |> maybe_filter_country(country)
    |> maybe_filter_status(status)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
    |> Enum.map(&to_public/1)
  end

  defp maybe_filter_country(query, nil), do: query
  defp maybe_filter_country(query, ""), do: query

  defp maybe_filter_country(query, country) do
    from a in query, where: a.country == ^country
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, ""), do: query

  defp maybe_filter_status(query, status) do
    from a in query, where: a.status == ^status
  end

  defp to_public(%Application{} = app) do
    %{
      id: app.id,
      country: app.country,
      full_name: app.full_name,
      amount: app.amount,
      monthly_income: app.monthly_income,
      status: app.status,
      risk_score: app.risk_score,
      inserted_at: app.inserted_at
    }
  end
end
