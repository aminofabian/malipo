defmodule MalipoWeb.PaymentControllerTest do
  use MalipoWeb.ConnCase, async: false

  alias Malipo.Merchants
  alias Malipo.Rails.TokenCache

  setup do
    bypass = Bypass.open()
    base = "http://127.0.0.1:#{bypass.port}"
    previous = Application.get_env(:malipo, :daraja, [])

    Application.put_env(:malipo, :daraja,
      consumer_key: "key",
      consumer_secret: "secret",
      shortcode: "4094529",
      passkey: "live-passkey-not-sandbox",
      environment: "sandbox",
      shortcode_type: "paybill",
      base_url: base,
      callback_base: "https://kiosk.ke"
    )

    TokenCache.invalidate({"key", base})
    on_exit(fn -> Application.put_env(:malipo, :daraja, previous) end)

    {:ok, _} =
      Merchants.put_destination("biz_pay", %{"kind" => "till", "till_number" => "5738421"})

    {:ok, _} = Merchants.confirm_destination("biz_pay")
    {:ok, keys} = Merchants.provision_keys("biz_pay")

    Bypass.stub(bypass, "GET", "/oauth/v1/generate", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"access_token":"tok_test","expires_in":3599}))
    end)

    Bypass.stub(bypass, "POST", "/mpesa/stkpush/v1/processrequest", fn conn ->
      body =
        File.read!(
          Path.join([File.cwd!(), "test/malipo/rails/daraja/fixtures/stk_push_accepted.json"])
        )

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, body)
    end)

    {:ok, keys: keys}
  end

  defp basic(conn, keys) do
    token = Base.encode64("#{keys.client_id}:#{keys.client_secret}")
    put_req_header(conn, "authorization", "Basic #{token}")
  end

  test "POST /v1/payments creates STK intent", %{conn: conn, keys: keys} do
    body =
      conn
      |> basic(keys)
      |> post(~p"/v1/payments", %{
        "amount" => "1.00",
        "currency" => "KES",
        "customer_phone" => "0712345678",
        "reference" => "TEST-1",
        "idempotency_key" => "merchant-test-1"
      })
      |> json_response(201)

    assert body["status"] == "pending"
    assert body["amount"] == "1.00"
    assert body["reference"] == "TEST-1"
    assert body["receipt"] == nil
    assert is_binary(body["id"])

    shown =
      conn
      |> basic(keys)
      |> get(~p"/v1/payments/#{body["id"]}")
      |> json_response(200)

    assert shown["id"] == body["id"]
    assert shown["callback_url"] == nil
  end

  test "POST /v1/payments stores callback_url and echoes it", %{conn: conn, keys: keys} do
    callback = "https://shop.example/payments/malipo"

    body =
      conn
      |> basic(keys)
      |> post(~p"/v1/payments", %{
        "amount" => "1.00",
        "customer_phone" => "0712345678",
        "reference" => "TEST-CB",
        "idempotency_key" => "merchant-test-cb",
        "callback_url" => callback
      })
      |> json_response(201)

    assert body["callback_url"] == callback
  end

  test "POST /v1/payments rejects a non-https callback_url", %{conn: conn, keys: keys} do
    body =
      conn
      |> basic(keys)
      |> post(~p"/v1/payments", %{
        "amount" => "1.00",
        "customer_phone" => "0712345678",
        "idempotency_key" => "merchant-test-bad-cb",
        "callback_url" => "http://shop.example/hook"
      })
      |> json_response(422)

    assert body["error"] == "invalid_callback_url"
  end

  test "POST /v1/payments falls back to the saved website URL", %{conn: conn, keys: keys} do
    {:ok, _} = Merchants.set_webhook_url("biz_pay", "https://shop.example/hooks/malipo")

    body =
      conn
      |> basic(keys)
      |> post(~p"/v1/payments", %{
        "amount" => "1.00",
        "customer_phone" => "0712345678",
        "idempotency_key" => "merchant-test-default-cb"
      })
      |> json_response(201)

    assert body["callback_url"] == "https://shop.example/hooks/malipo"
  end

  test "POST /v1/payments accepts the secret as a bearer token", %{conn: conn, keys: keys} do
    body =
      conn
      |> put_req_header("authorization", "Bearer #{keys.client_secret}")
      |> post(~p"/v1/payments", %{
        "amount" => "1.00",
        "customer_phone" => "0712345678",
        "reference" => "BEARER-1",
        "idempotency_key" => "merchant-test-bearer"
      })
      |> json_response(201)

    assert body["status"] == "pending"
    assert body["reference"] == "BEARER-1"
  end

  test "rejects missing auth", %{conn: conn} do
    conn
    |> post(~p"/v1/payments", %{"amount" => "1.00"})
    |> json_response(401)
  end
end
