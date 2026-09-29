defmodule Malipo.Intents.PushReconcileTest do
  use Malipo.DataCase, async: false

  alias Malipo.Intents
  alias Malipo.Intents.Intent
  alias Malipo.Rails.TokenCache

  setup do
    bypass = Bypass.open()
    base = "http://127.0.0.1:#{bypass.port}"

    creds = %{
      "consumerKey" => "key",
      "consumerSecret" => "secret",
      "shortcode" => "4094529",
      "passkey" => "live-passkey-not-sandbox",
      "environment" => "sandbox",
      "shortcodeType" => "paybill",
      "base_url" => base
    }

    TokenCache.invalidate({"key", base})

    Bypass.expect(bypass, "GET", "/oauth/v1/generate", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"access_token":"tok_test","expires_in":3599}))
    end)

    {:ok, bypass: bypass, creds: creds}
  end

  defp fixture(name) do
    Path.join([File.cwd!(), "test/malipo/rails/daraja/fixtures", name]) |> File.read!()
  end

  defp pending_intent!(key) do
    assert {:ok, intent} =
             Intents.create(%{
               business_id: "biz_rail",
               idempotency_key: key,
               amount: "100.00",
               payer_msisdn: "0712345678",
               context: %{"type" => "POS_PAYMENT", "id" => "sale_x"}
             })

    intent
  end

  test "push_stk prompts on accept", %{bypass: bypass, creds: creds} do
    Bypass.expect(bypass, "POST", "/mpesa/stkpush/v1/processrequest", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, fixture("stk_push_accepted.json"))
    end)

    intent = pending_intent!("push-stk-ok-001")

    assert {:ok, %Intent{status: "prompted"} = prompted} =
             Intents.push_stk(intent, creds, callback_url: "https://kiosk.ke")

    assert prompted.checkout_request_id == "ws_CO_190920261234_ABC"
  end

  test "push_stk fails the intent on Wrong credentials", %{bypass: bypass, creds: creds} do
    Bypass.expect(bypass, "POST", "/mpesa/stkpush/v1/processrequest", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(400, fixture("stk_push_wrong_credentials.json"))
    end)

    intent = pending_intent!("push-stk-bad-001")

    assert {:error, %{kind: :bad_passkey}} =
             Intents.push_stk(intent, creds, callback_url: "https://kiosk.ke")

    assert %Intent{status: "failed", failure_kind: "bad_passkey"} = Intents.get!(intent.id)
  end

  test "reconcile_prompted settles on success", %{bypass: bypass, creds: creds} do
    Bypass.expect(bypass, "POST", "/mpesa/stkpush/v1/processrequest", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, fixture("stk_push_accepted.json"))
    end)

    Bypass.expect(bypass, "POST", "/mpesa/stkpushquery/v1/query", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, fixture("stk_query_success.json"))
    end)

    intent = pending_intent!("reconcile-ok-001")
    {:ok, prompted} = Intents.push_stk(intent, creds, callback_url: "https://kiosk.ke")

    assert {:ok, %Intent{status: "settled", receipt: "SJH4K2LM9P"}} =
             Intents.reconcile_prompted(prompted, creds)
  end

  test "reconcile_prompted stays pending while Safaricom processes", %{
    bypass: bypass,
    creds: creds
  } do
    Bypass.expect(bypass, "POST", "/mpesa/stkpush/v1/processrequest", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, fixture("stk_push_accepted.json"))
    end)

    Bypass.expect(bypass, "POST", "/mpesa/stkpushquery/v1/query", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, fixture("stk_query_pending.json"))
    end)

    intent = pending_intent!("reconcile-pending-001")
    {:ok, prompted} = Intents.push_stk(intent, creds, callback_url: "https://kiosk.ke")

    assert {:pending, %Intent{status: "prompted"}} =
             Intents.reconcile_prompted(prompted, creds)
  end

  test "reconcile_prompted fails on customer cancel", %{bypass: bypass, creds: creds} do
    Bypass.expect(bypass, "POST", "/mpesa/stkpush/v1/processrequest", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, fixture("stk_push_accepted.json"))
    end)

    Bypass.expect(bypass, "POST", "/mpesa/stkpushquery/v1/query", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, fixture("stk_query_cancelled.json"))
    end)

    intent = pending_intent!("reconcile-cancel-001")
    {:ok, prompted} = Intents.push_stk(intent, creds, callback_url: "https://kiosk.ke")

    assert {:ok, %Intent{status: "failed", failure_kind: "subscriber_cancelled"}} =
             Intents.reconcile_prompted(prompted, creds)
  end
end
