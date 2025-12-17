alias BravoMultipais.{Repo, Accounts.User}
alias Bcrypt

{:ok, _} = Application.ensure_all_started(:bcrypt_elixir)

email = "admin@example.com"

user =
  Repo.get_by(User, email: email) ||
    %User{email: email}
    |> Ecto.Changeset.change(%{
      hashed_password: Bcrypt.hash_pwd_salt("bravo_demo_1234"),
      confirmed_at: DateTime.utc_now(),
      role: "backoffice"
    })
    |> Repo.insert!()

IO.puts("""
Seed backoffice user:

  email: #{email}
  password: bravo_demo_1234
""")
