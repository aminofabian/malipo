defmodule MalipoWeb.Plugs.ServiceAuth do
  @moduledoc """
  Bearer token gate for `/internal/*`.

  When `MALIPO_SERVICE_TOKEN` (or `:service_token` config) is set, requests must
  send `Authorization: Bearer <token>`. When unset (local dark-mode / test),
  the plug is a no-op — mTLS at the edge is the production perimeter.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case service_token() do
      token when is_binary(token) and token != "" ->
        verify(conn, token)

      _ ->
        conn
    end
  end

  defp verify(conn, expected) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> got] ->
        if secure_compare(got, expected) do
          conn
        else
          unauthorized(conn)
        end

      _ ->
        unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
    |> halt()
  end

  defp service_token do
    Application.get_env(:malipo, :service_token) || System.get_env("MALIPO_SERVICE_TOKEN")
  end

  defp secure_compare(a, b) when is_binary(a) and is_binary(b) do
    Plug.Crypto.secure_compare(a, b)
  end
end
