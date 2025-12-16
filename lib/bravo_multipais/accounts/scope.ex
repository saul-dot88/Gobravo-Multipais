defmodule BravoMultipais.Accounts.Scope do
  @moduledoc """
  Representa el alcance de autenticación actual:

    * user  -> el usuario autenticado
    * role  -> rol del usuario (ej. "backoffice", "external")
    * authenticated_at -> cuándo se autenticó la sesión (opcional)
  """

  alias BravoMultipais.Accounts.User

  defstruct [
    :user,
    :role,
    :authenticated_at
  ]

  @type t :: %__MODULE__{
          user: User.t() | nil,
          role: String.t() | nil,
          authenticated_at: DateTime.t() | nil
        }
end
