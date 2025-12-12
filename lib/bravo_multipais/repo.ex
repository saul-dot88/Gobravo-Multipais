defmodule BravoMultipais.Repo do
  use Ecto.Repo,
    otp_app: :bravo_multipais,
    adapter: Ecto.Adapters.Postgres
end
