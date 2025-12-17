# priv/repo/seeds.exs

alias BravoMultipais.Accounts

demo_email = "demo@bravo-multipais.dev"

demo_attrs = %{
  email: demo_email,
  password: "secret1234",
  # ajusta este valor para que sea compatible con tu Scope.for_user/1
  role: "admin"
}

user =
  case Accounts.get_user_by_email(demo_email) do
    nil ->
      # Ojo: si en tu contexto no se llama register_user/1,
      # cámbialo por la función que uses para crear usuarios.
      case Accounts.register_user(demo_attrs) do
        {:ok, user} ->
          IO.puts("Usuario demo creado: #{user.email}")
          user

        {:error, changeset} ->
          IO.inspect(changeset.errors, label: " Error creando usuario demo")
          raise "No se pudo crear el usuario demo"
      end

    user ->
      IO.puts("Usuario demo ya existía: #{user.email}")
      user
  end

IO.inspect(user, label: "Usuario demo listo")
