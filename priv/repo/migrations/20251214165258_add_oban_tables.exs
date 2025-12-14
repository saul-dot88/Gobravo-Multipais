defmodule BravoMultipais.Repo.Migrations.AddObanTables do
  use Ecto.Migration

  def up do
    # Crea todas las tablas necesarias de Oban hasta la versión 11
    Oban.Migrations.up(version: 11)
  end

  def down do
    # Si quieres revertir todo lo de Oban
    Oban.Migrations.down(version: 0)
  end
end
