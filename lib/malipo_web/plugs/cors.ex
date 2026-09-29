defmodule MalipoWeb.Plugs.Cors do
  @moduledoc """
  Permissive CORS for the public, read-only fees endpoints so the static
  marketing site can render the live schedule.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "content-type, accept")
  end
end
