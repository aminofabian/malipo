defmodule Malipo.Merchants.WebhooksTest do
  use Malipo.DataCase, async: false

  alias Malipo.Merchants
  alias Malipo.Merchants.Webhooks
  alias Malipo.Outbox.Dispatcher
  alias Malipo.Outbox.Event
  alias Malipo.Repo

  test "sign is deterministic HMAC-SHA256 hex" do
    assert Webhooks.sign("{\"a\":1}", "whsec_test") ==
             Webhooks.sign("{\"a\":1}", "whsec_test")

    refute Webhooks.sign("{\"a\":1}", "whsec_test") == Webhooks.sign("{\"a\":2}", "whsec_test")
  end

  test "deliver POSTs signed payment.settled to merchant URL" do
    bypass = Bypass.open()

    assert {:ok, _} =
             Merchants.put_destination("biz_wh", %{
               "kind" => "till",
               "till_number" => "5738421"
             })

    assert {:ok, _} = Merchants.confirm_destination("biz_wh")
    assert {:ok, revealed} = Merchants.provision_keys("biz_wh")

    assert {:ok, _} =
             Merchants.set_webhook_url("biz_wh", "http://127.0.0.1:#{bypass.port}/hooks")

    Bypass.expect_once(bypass, "POST", "/hooks", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      [sig] = Plug.Conn.get_req_header(conn, "x-malipo-signature")
      assert String.starts_with?(sig, "sha256=")
      digest = String.trim_leading(sig, "sha256=")
      assert digest == Webhooks.sign(body, revealed.webhook_secret)

      payload = Jason.decode!(body)
      assert payload["event"] == "payment.settled"
      assert payload["data"]["status"] == "settled"
      assert payload["data"]["amount"] == "1.00"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"ok":true}))
    end)

    assert :ok =
             Webhooks.deliver("biz_wh", %{
               "event_id" => "evt_1",
               "event" => "intent.settled",
               "occurred_at" => "2026-09-21T00:00:00Z",
               "business_id" => "biz_wh",
               "intent_id" => "intent-1",
               "amount" => "1.00",
               "currency" => "KES",
               "context" => %{"reference" => "TEST"},
               "receipt" => "ABC123"
             })
  end

  test "dispatcher marks delivered when merchant webhook succeeds" do
    bypass = Bypass.open()

    assert {:ok, _} =
             Merchants.put_destination("biz_wh2", %{
               "kind" => "till",
               "till_number" => "1111111"
             })

    assert {:ok, _} = Merchants.confirm_destination("biz_wh2")
    assert {:ok, _} = Merchants.provision_keys("biz_wh2")
    assert {:ok, _} = Merchants.set_webhook_url("biz_wh2", "http://127.0.0.1:#{bypass.port}/h")

    Bypass.expect_once(bypass, "POST", "/h", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, "{}")
    end)

    {:ok, row} =
      %{
        event_id: "evt_dispatch_1",
        event: "intent.settled",
        business_id: "biz_wh2",
        payload: %{
          "event" => "intent.settled",
          "event_id" => "evt_dispatch_1",
          "occurred_at" => DateTime.to_iso8601(DateTime.utc_now()),
          "business_id" => "biz_wh2",
          "intent_id" => Ecto.UUID.generate(),
          "amount" => "10.00",
          "currency" => "KES",
          "context" => %{},
          "receipt" => "R1"
        },
        next_attempt_at: DateTime.utc_now()
      }
      |> Event.create_changeset()
      |> Repo.insert()

    assert :ok = Dispatcher.perform(%Oban.Job{args: %{"outbox_id" => row.id}})
    assert Repo.get!(Event, row.id).status == "delivered"
  end

  test "deliver POSTs to the payment callback_url and ignores the account webhook" do
    bypass = Bypass.open()

    assert {:ok, _} =
             Merchants.put_destination("biz_cb", %{
               "kind" => "till",
               "till_number" => "2222222"
             })

    assert {:ok, _} = Merchants.confirm_destination("biz_cb")
    assert {:ok, revealed} = Merchants.provision_keys("biz_cb")

    assert {:ok, _} =
             Merchants.set_webhook_url("biz_cb", "http://127.0.0.1:#{bypass.port}/account")

    Bypass.expect_once(bypass, "POST", "/payment", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      [sig] = Plug.Conn.get_req_header(conn, "x-malipo-signature")
      digest = String.trim_leading(sig, "sha256=")
      assert digest == Webhooks.sign(body, revealed.webhook_secret)
      assert Jason.decode!(body)["event"] == "payment.failed"

      Plug.Conn.resp(conn, 200, "{}")
    end)

    assert :ok =
             Webhooks.deliver("biz_cb", %{
               "event_id" => "evt_cb",
               "event" => "intent.failed",
               "occurred_at" => "2026-09-21T00:00:00Z",
               "business_id" => "biz_cb",
               "intent_id" => "intent-cb",
               "amount" => "50.00",
               "currency" => "KES",
               "context" => %{
                 "reference" => "ORD-9",
                 "callback_url" => "http://127.0.0.1:#{bypass.port}/payment"
               },
               "failure_kind" => "cancelled",
               "failure_message" => "Cancelled"
             })
  end

  test "deliver skips when the payment has no callback and no account webhook" do
    assert {:ok, _} =
             Merchants.put_destination("biz_nocb", %{
               "kind" => "till",
               "till_number" => "3333333"
             })

    assert {:ok, _} = Merchants.confirm_destination("biz_nocb")
    assert {:ok, _} = Merchants.provision_keys("biz_nocb")

    assert :ok =
             Webhooks.deliver("biz_nocb", %{
               "event" => "intent.settled",
               "event_id" => "evt_none",
               "context" => %{"reference" => "ORD-1"},
               "amount" => "1.00",
               "currency" => "KES",
               "receipt" => "R"
             })
  end
end
