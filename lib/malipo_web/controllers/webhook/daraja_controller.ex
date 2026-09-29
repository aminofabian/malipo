defmodule MalipoWeb.Webhook.DarajaController do
  @moduledoc """
  Daraja webhook endpoints — persist raw body, always 200.

  Paths match the provider-registered URLs byte-for-byte (§7.1):
  `/webhooks/daraja/stk`, `/c2b/validation`, `/c2b/confirmation`, `/b2b/*`.
  """

  use MalipoWeb, :controller

  alias MalipoWeb.Plugs.CacheBodyReader
  alias Malipo.Webhooks

  @doc "STK push callback."
  def stk(conn, _params) do
    ingest_and_ack(conn, "stk")
  end

  @doc "C2B validation — Accept so Safaricom proceeds to confirmation."
  def c2b_validation(conn, _params) do
    _ = ingest(conn, "c2b_validation")

    json(conn, %{"ResultCode" => 0, "ResultDesc" => "Accepted"})
  end

  @doc "C2B confirmation."
  def c2b_confirmation(conn, _params) do
    ingest_and_ack(conn, "c2b_confirmation")
  end

  @doc "Provider business-transfer result."
  def b2b_result(conn, _params) do
    ingest_and_ack(conn, "b2b_result")
  end

  @doc "Provider business-transfer timeout."
  def b2b_timeout(conn, _params) do
    ingest_and_ack(conn, "b2b_timeout")
  end

  defp ingest_and_ack(conn, kind) do
    _ = ingest(conn, kind)
    send_resp(conn, 200, "OK")
  end

  defp ingest(conn, kind) do
    raw = CacheBodyReader.raw_body(conn)
    raw = if raw == "", do: Jason.encode!(conn.body_params), else: raw
    headers = Map.new(conn.req_headers)

    case Webhooks.ingest(kind, raw, headers) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end
end
