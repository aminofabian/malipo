defmodule Malipo.SandboxTest do
  use Malipo.DataCase, async: false
  use Oban.Testing, repo: Malipo.Repo

  alias Malipo.Intents
  alias Malipo.Merchants
  alias Malipo.Outbox
  alias Malipo.Outbox.Dispatcher
  alias Malipo.Outbox.Event
  alias Malipo.Rails.TokenCache
  alias Malipo.Sandbox

  defp attrs(number, key) do
    %{
      "business_id" => "biz_sbx",
      "mode" => "test",
      "amount" => "1.00",
      "currency" => "KES",
      "payer_msisdn" => number,
      "idempotency_key" => key
    }
  end

  test "reserved success number settles immediately with a synthetic receipt" do
    assert {:ok, intent} = Intents.create_and_push(attrs("254000000001", "sbx-ok-1"))

    assert intent.mode == "test"
    assert intent.status == "settled"
    assert String.starts_with?(intent.receipt, "TEST")

    # The settle writes a test-tagged outbox event (carrying the merchant
    # webhook) but accrues no fee sweep.
    assert [%{mode: "test"}] = Outbox.list_recent(50, "test")
    refute_enqueued(queue: :fee_sweep)
  end

  test "reserved failure numbers fail with the mapped kind" do
    assert {:ok, insufficient} = Intents.create_and_push(attrs("254000000002", "sbx-fail-1"))
    assert insufficient.status == "failed"
    assert insufficient.failure_kind == "insufficient_funds"

    assert {:ok, wrong_pin} = Intents.create_and_push(attrs("254000000003", "sbx-fail-2"))
    assert wrong_pin.failure_kind == "wrong_pin"
  end

  test "a normal number prompts, then auto-settles via Oban" do
    assert {:ok, intent} = Intents.create_and_push(attrs("254712345678", "sbx-auto-1"))
    assert intent.status == "prompted"
    assert String.starts_with?(intent.checkout_request_id, "ws_CO_test_")

    assert_enqueued(worker: Malipo.Sandbox.AutoSettle, args: %{"intent_id" => intent.id})

    assert {:ok, settled} = Sandbox.settle(intent)
    assert settled.status == "settled"
  end

  test "simulate forces a terminal state deterministically" do
    assert {:ok, intent} = Intents.create_and_push(attrs("254799999999", "sbx-sim-1"))
    assert intent.status == "prompted"

    assert {:ok, failed} = Sandbox.simulate(intent, :failed, "wrong_pin")
    assert failed.status == "failed"
    assert failed.failure_kind == "wrong_pin"

    assert {:ok, other} = Intents.create_and_push(attrs("254799999998", "sbx-sim-2"))
    assert {:ok, settled} = Sandbox.simulate(other, :settled, nil)
    assert settled.status == "settled"
  end

  test "simulate rejects an unknown failure kind" do
    assert {:ok, intent} = Intents.create_and_push(attrs("254799999997", "sbx-sim-3"))
    assert {:error, :invalid_failure_kind} = Sandbox.simulate(intent, :failed, "not_a_kind")
  end

  test "reserved msisdn normalisation" do
    assert Sandbox.reserved?("254000000001")
    assert {:ok, "254000000001"} = Sandbox.normalise_msisdn("254000000001")
    assert {:ok, "254000000001"} = Sandbox.normalise_msisdn("254 000 000001")
    refute Sandbox.reserved?("254712345678")
    assert :error = Sandbox.normalise_msisdn("254712345678")
  end

  test "no Daraja call is made for a test intent" do
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

    on_exit(fn -> Application.put_env(:malipo, :daraja, previous) end)
    TokenCache.invalidate({"key", base})

    test_pid = self()

    Bypass.stub(bypass, "GET", "/oauth/v1/generate", fn conn ->
      send(test_pid, :daraja_called)
      Plug.Conn.resp(conn, 200, ~s({"access_token":"tok","expires_in":3599}))
    end)

    Bypass.stub(bypass, "POST", "/mpesa/stkpush/v1/processrequest", fn conn ->
      send(test_pid, :daraja_called)
      Plug.Conn.resp(conn, 200, ~s({"ResponseCode":"0"}))
    end)

    assert {:ok, intent} = Intents.create_and_push(attrs("254000000001", "sbx-nodaraja"))
    assert intent.status == "settled"
    refute_received :daraja_called
  end

  test "a sandbox settle fires a test-signed webhook and skips the monolith" do
    hooks = Bypass.open()
    monolith = Bypass.open()
    test_pid = self()

    previous = Application.get_env(:malipo, :monolith_payment_events_url)

    Application.put_env(
      :malipo,
      :monolith_payment_events_url,
      "http://127.0.0.1:#{monolith.port}/events"
    )

    on_exit(fn -> Application.put_env(:malipo, :monolith_payment_events_url, previous) end)

    {:ok, test_keys} = Merchants.provision_keys("biz_wh_sbx", "test")

    {:ok, _} =
      Merchants.set_webhook_url("biz_wh_sbx", "http://127.0.0.1:#{hooks.port}/hooks", "test")

    Bypass.expect_once(hooks, "POST", "/hooks", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      [sig] = Plug.Conn.get_req_header(conn, "x-malipo-signature")
      digest = String.trim_leading(sig, "sha256=")
      assert digest == Malipo.Merchants.Webhooks.sign(body, test_keys.webhook_secret)
      assert Jason.decode!(body)["event"] == "payment.settled"
      Plug.Conn.resp(conn, 200, "{}")
    end)

    Bypass.stub(monolith, "POST", "/events", fn conn ->
      send(test_pid, :monolith_called)
      Plug.Conn.resp(conn, 200, "{}")
    end)

    assert {:ok, intent} =
             Intents.create_and_push(%{
               "business_id" => "biz_wh_sbx",
               "mode" => "test",
               "amount" => "1.00",
               "currency" => "KES",
               "payer_msisdn" => "254000000001",
               "idempotency_key" => "sbx-wh-1"
             })

    assert intent.status == "settled"

    row = Repo.get_by(Event, intent_id: intent.id)
    assert row.mode == "test"

    assert :ok = Dispatcher.perform(%Oban.Job{args: %{"outbox_id" => row.id}})
    refute_received :monolith_called
  end
end
