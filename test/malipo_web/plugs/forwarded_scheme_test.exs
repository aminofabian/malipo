defmodule MalipoWeb.Plugs.ForwardedSchemeTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias MalipoWeb.Plugs.ForwardedScheme

  defp run(conn), do: ForwardedScheme.call(conn, ForwardedScheme.init([]))

  test "cf-visitor https marks the conn as https even when x-forwarded-proto says http" do
    conn =
      conn(:get, "/ready")
      |> put_req_header("cf-visitor", ~s({"scheme":"https"}))
      |> put_req_header("x-forwarded-proto", "http")
      |> run()

    assert conn.scheme == :https
    assert conn.port == 443
  end

  test "x-forwarded-proto https marks the conn as https" do
    conn = conn(:get, "/ready") |> put_req_header("x-forwarded-proto", "https") |> run()

    assert conn.scheme == :https
  end

  test "plain http stays http" do
    conn =
      conn(:get, "/ready")
      |> put_req_header("cf-visitor", ~s({"scheme":"http"}))
      |> run()

    assert conn.scheme == :http
  end
end
