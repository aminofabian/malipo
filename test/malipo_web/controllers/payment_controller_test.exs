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

  test "a test key creates a sandbox payment, never a live one (sandbox rule 1)", %{conn: conn} do
    {:ok, test_keys} = Merchants.provision_keys("biz_pay_test", "test")

    body =
      conn
      |> put_req_header("authorization", "Bearer #{test_keys.client_secret}")
      |> post(~p"/v1/payments", %{
        "amount" => "1.00",
        "customer_phone" => "0712345678",
        "idempotency_key" => "test-key-sandbox"
      })
      |> json_response(201)

    intent = Malipo.Intents.get(body["id"])
    assert intent.mode == "test"
    assert String.starts_with?(intent.checkout_request_id, "ws_CO_test_")
  end

  describe "sandbox (test mode)" do
    defp test_key do
      {:ok, keys} = Merchants.provision_keys("biz_pay", "test")
      keys
    end

    defp bearer(conn, secret), do: put_req_header(conn, "authorization", "Bearer #{secret}")

    test "a test key creates a simulated settled payment (reserved number)", %{conn: conn} do
      keys = test_key()

      body =
        conn
        |> bearer(keys.client_secret)
        |> post(~p"/v1/payments", %{
          "amount" => "1.00",
          "customer_phone" => "254000000001",
          "reference" => "SBX-OK",
          "idempotency_key" => "sbx-ok-ctrl"
        })
        |> json_response(201)

      assert body["status"] == "settled"
      assert String.starts_with?(body["receipt"], "TEST")
      assert body["reference"] == "SBX-OK"
    end

    test "a test key can force a failure with simulate", %{conn: conn} do
      keys = test_key()

      created =
        conn
        |> bearer(keys.client_secret)
        |> post(~p"/v1/payments", %{
          "amount" => "5.00",
          "customer_phone" => "254712345678",
          "idempotency_key" => "sbx-sim-ctrl"
        })
        |> json_response(201)

      assert created["status"] == "pending"

      sim =
        conn
        |> bearer(keys.client_secret)
        |> post(~p"/v1/payments/#{created["id"]}/simulate", %{
          "outcome" => "failed",
          "failure_kind" => "wrong_pin"
        })
        |> json_response(200)

      assert sim["status"] == "failed"
      assert sim["failure_kind"] == "wrong_pin"
    end

    test "a test key cannot see a live payment of the same business", %{conn: conn, keys: live} do
      live_payment =
        conn
        |> basic(live)
        |> post(~p"/v1/payments", %{
          "amount" => "1.00",
          "customer_phone" => "0712345678",
          "idempotency_key" => "live-only-1"
        })
        |> json_response(201)

      test_keys = test_key()

      conn
      |> bearer(test_keys.client_secret)
      |> get(~p"/v1/payments/#{live_payment["id"]}")
      |> json_response(404)
    end

    test "a live key cannot call simulate", %{conn: conn, keys: live} do
      conn
      |> basic(live)
      |> post(~p"/v1/payments/00000000-0000-0000-0000-000000000000/simulate", %{
        "outcome" => "settled"
      })
      |> json_response(403)
    end

    test "simulate is 404 for an unknown id", %{conn: conn} do
      keys = test_key()

      conn
      |> bearer(keys.client_secret)
      |> post(~p"/v1/payments/00000000-0000-0000-0000-000000000000/simulate", %{
        "outcome" => "settled"
      })
      |> json_response(404)
    end
  end
end
