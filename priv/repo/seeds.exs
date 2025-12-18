# priv/repo/seeds.exs

alias BravoMultipais.{Accounts, Repo}
alias BravoMultipais.Accounts.User
alias Ecto.Changeset

demo_email = "demo@bravo-multipais.dev"

# Solo necesitamos el email, el resto lo maneja el contexto
demo_attrs = %{
  email: demo_email
}

user =
  case Accounts.get_user_by_email(demo_email) do
    nil ->
      case Accounts.register_user(demo_attrs) do
        {:ok, user} ->
          IO.puts("Usuario demo creado: #{user.email}")
          user

        {:error, changeset} ->
          IO.inspect(changeset.errors, label: "Error creando usuario demo")
          raise "No se pudo crear el usuario demo"
      end

    user ->
      IO.puts("Usuario demo ya existía: #{user.email}")
      user
  end

# Aseguramos que el usuario demo tenga rol "backoffice"
user =
  user
  |> Changeset.change(role: "backoffice")
  |> Repo.update!()

IO.inspect(user, label: "Usuario demo listo (rol backoffice)")
