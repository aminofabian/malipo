defmodule MalipoWeb.Plugs.ForwardedScheme do
  @moduledoc """
  Marks the connection as HTTPS when the visitor reached Cloudflare over TLS.

  Cloudflare (Flexible SSL) talks to the origin over plain HTTP and Traefik
  overwrites `x-forwarded-proto` with `http`, so `cf-visitor` is the only
  reliable signal of the visitor's real scheme.
  """

  @behaviour Plug

  @https "https"
  @https_port 443

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if visitor_https?(conn) do
      %{conn | scheme: :https, port: @https_port}
    else
      conn
    end
  end

  defp visitor_https?(conn) do
    cf_visitor_https?(conn) or forwarded_proto_https?(conn)
  end

  defp cf_visitor_https?(conn) do
    case Plug.Conn.get_req_header(conn, "cf-visitor") do
      [raw | _] -> String.contains?(raw, ~s("scheme":"#{@https}"))
      [] -> false
    end
  end

  defp forwarded_proto_https?(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-proto") do
      [proto | _] -> proto |> String.split(",") |> hd() |> String.trim() == @https
      [] -> false
    end
  end
end
