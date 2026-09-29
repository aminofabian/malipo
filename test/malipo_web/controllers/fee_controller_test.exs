defmodule MalipoWeb.FeeControllerTest do
  use MalipoWeb.ConnCase, async: false

  test "GET /v1/fees returns the schedule and CORS header", %{conn: conn} do
    body = conn |> get(~p"/v1/fees") |> json_response(200)

    assert body["currency"] == "KES"
    assert body["sms_rate"] == "0.80"
    assert body["whatsapp_rate"] == "0.60"
    assert length(body["bands"]) == 20

    first = hd(body["bands"])
    assert first["from"] == 1
    assert first["to"] == 10
    assert first["fee"] == 0
  end

  test "GET /v1/fees/quote returns the fee and net", %{conn: conn} do
    body = conn |> get(~p"/v1/fees/quote?amount=1000") |> json_response(200)
    assert body["amount"] == "1000"
    assert body["fee"] == "15"
    assert body["net"] == "985"
  end

  test "GET /v1/fees/quote rejects a missing or bad amount", %{conn: conn} do
    assert %{"error" => "invalid_amount"} =
             conn |> get(~p"/v1/fees/quote") |> json_response(422)

    assert %{"error" => "invalid_amount"} =
             conn |> get(~p"/v1/fees/quote?amount=abc") |> json_response(422)
  end

  test "OPTIONS /v1/fees answers a CORS preflight", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", "https://kiosk.ke")
      |> put_req_header("access-control-request-method", "GET")
      |> dispatch(MalipoWeb.Endpoint, :options, ~p"/v1/fees")

    assert conn.status == 204
    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
  end
end
