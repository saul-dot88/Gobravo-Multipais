defmodule BravoMultipais.Accounts.Scope do
  @moduledoc """
  Representa el *scope* del usuario autenticado (user + rol + metadata).

  - `user`: struct de `BravoMultipais.Accounts.User`
  - `role`: string, por ahora `"backoffice"` o `"external"`
  - `authenticated_at`: fecha en la que se autenticó (si aplica)
  """

  alias BravoMultipais.Accounts.User

  defstruct [:user, :role, :authenticated_at]

  @type t :: %__MODULE__{
          user: User.t(),
          role: String.t(),
          authenticated_at: DateTime.t() | nil
        }

  @doc """
  Construye un scope a partir de un usuario.

  - Si el usuario es `nil`, regresamos `nil` (útil en pantallas públicas como login).
  - El rol se toma de `user.role` o `"external"` si viene `nil`.
  """
  @spec for_user(User.t() | nil, DateTime.t() | nil) :: t() | nil
  def for_user(nil, _authenticated_at), do: nil

  def for_user(%User{} = user, authenticated_at \\ nil) do
    %__MODULE__{
      user: user,
      role: user.role || "external",
      authenticated_at: authenticated_at
    }
  end
end
