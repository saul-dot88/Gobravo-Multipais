defmodule BravoMultipaisWeb.PageController do
  use BravoMultipaisWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
