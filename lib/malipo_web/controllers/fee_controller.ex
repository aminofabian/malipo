defmodule MalipoWeb.FeeController do
  @moduledoc "Public, read-only fee schedule and quotes — `/v1/fees`."

  use MalipoWeb, :controller

  alias Malipo.Fees

  @doc "GET /v1/fees — the current schedule and notification rates."
  def show(conn, _params) do
    json(conn, Fees.public_view())
  end

  @doc "GET /v1/fees/quote?amount=1000 — the fee and net for an amount."
  def quote(conn, %{"amount" => amount}) do
    case Fees.quote(amount) do
      {:ok, %{fee: fee, net: net}} ->
        json(conn, %{
          "amount" => to_string(amount),
          "currency" => "KES",
          "fee" => Decimal.to_string(fee),
          "net" => Decimal.to_string(net)
        })

      {:error, :invalid_amount} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{"error" => "invalid_amount"})
    end
  end

  def quote(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{"error" => "invalid_amount"})
  end

  @doc "OPTIONS /v1/fees — CORS preflight (headers are set by the pipeline plug)."
  def preflight(conn, _params) do
    send_resp(conn, :no_content, "")
  end
end
