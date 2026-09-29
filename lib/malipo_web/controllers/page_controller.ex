defmodule MalipoWeb.PageController do
  use MalipoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
