defmodule BravoMultipais.CreditApplications.Queries do
  import Ecto.Query, only: [from: 2]
  alias BravoMultipais.{Repo, CreditApplications.Application}

  def get_application(id), do: Repo.get(Application, id)

  def list_applications(params \\ %{}) do
    country = Map.get(params, "country")
    status = Map.get(params, "status")

    Application
    |> maybe_filter_country(country)
    |> maybe_filter_status(status)
    |> Repo.all()
    |> Enum.map(&to_public/1)
  end

  defp maybe_filter_country(query, nil), do: query
  defp maybe_filter_country(query, country),
    do: from a in query, where: a.country == ^country

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status),
    do: from a in query, where: a.status == ^status

  # Simplificamos la forma en que regresamos las apps al index
  defp to_public(app) do
    %{
      id: app.id,
      country: app.country,
      full_name: app.full_name,
      amount: app.amount,
      monthly_income: app.monthly_income,
      status: app.status,
      inserted_at: app.inserted_at
    }
  end
end
