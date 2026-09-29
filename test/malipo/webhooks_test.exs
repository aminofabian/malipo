defmodule Malipo.WebhooksTest do
  use Malipo.DataCase, async: false

  alias Malipo.Intents
  alias Malipo.Intents.Intent
  alias Malipo.Outbox
  alias Malipo.Outbox.Event, as: OutboxEvent
  alias Malipo.Webhooks
  alias Malipo.Webhooks.Event

  defp fixture(name) do
    Path.join([File.cwd!(), "test/malipo/rails/daraja/fixtures", name]) |> File.read!()
  end

  defp prompted_intent!(key, checkout \\ "ws_CO_190920261234_ABC") do
    assert {:ok, intent} =
             Intents.create(%{
               business_id: "biz_wh",
               idempotency_key: key,
               amount: "100.00",
               payer_msisdn: "0712345678",
               context: %{"type" => "POS_PAYMENT", "id" => "sale_wh"}
             })

    assert {:ok, prompted} =
             Intents.mark_prompted(intent, %{
               checkout_request_id: checkout,
               merchant_request_id: "29115-34620561-1"
             })

    prompted
  end

  test "ingest persists raw STK body and dedupes on CheckoutRequestID" do
    body = fixture("stk_callback_success.json")

    assert {:ok, %Event{kind: "stk", status: "received"} = event} =
             Webhooks.ingest("stk", body, %{"x-forwarded-for" => "1.2.3.4"})

    assert event.dedupe_key == "ws_CO_190920261234_ABC"
    assert event.raw_body =~ "SJH4K2LM9P"

    assert {:ok, :duplicate} = Webhooks.ingest("stk", body, %{})
  end

  test "process settles prompted intent and writes outbox" do
    intent = prompted_intent!("wh-settle-001")
    body = fixture("stk_callback_success.json")

    assert {:ok, %Event{} = event} = Webhooks.ingest("stk", body)
    assert {:ok, %Event{status: "processed", intent_id: intent_id}} = Webhooks.process(event.id)
    assert intent_id == intent.id

    settled = Intents.get!(intent.id)
    assert settled.status == "settled"
    assert settled.receipt == "SJH4K2LM9P"

    assert [%OutboxEvent{event: "intent.settled", status: "pending"} = row] =
             Repo.all(OutboxEvent)

    assert row.payload["receipt"] == "SJH4K2LM9P"
    assert row.payload["payer"]["msisdn_masked"] == "2547****678"
  end

  test "process fails intent on customer cancel" do
    intent = prompted_intent!("wh-fail-001")
    body = fixture("stk_callback_cancelled.json")

    assert {:ok, event} = Webhooks.ingest("stk", body)
    assert {:ok, %{status: "processed"}} = Webhooks.process(event.id)

    failed = Intents.get!(intent.id)
    assert failed.status == "failed"
    assert failed.failure_kind == "subscriber_cancelled"

    assert [%OutboxEvent{event: "intent.failed"}] = Repo.all(OutboxEvent)
  end

  test "process is idempotent when intent already settled" do
    _intent = prompted_intent!("wh-idem-001")
    body = fixture("stk_callback_success.json")

    assert {:ok, e1} = Webhooks.ingest("stk", body)
    assert {:ok, _} = Webhooks.process(e1.id)

    # Second delivery with a different CheckoutRequestID suffix won't happen —
    # same dedupe means ingest returns duplicate. Simulate re-process:
    assert {:ok, %Event{status: "processed"}} = Webhooks.process(e1.id)

    assert [%OutboxEvent{}] = Repo.all(OutboxEvent)
  end

  test "outbox dispatcher succeeds when monolith URL is unset" do
    intent = prompted_intent!("wh-dispatch-001")

    assert {:ok, %Intent{status: "settled"}} =
             Intents.mark_settled(intent, %{receipt: "RCP_DISPATCH_1"})

    [row] = Repo.all(OutboxEvent)
    assert :ok = Malipo.Outbox.Dispatcher.perform(%Oban.Job{args: %{"outbox_id" => row.id}})

    assert %OutboxEvent{status: "delivered"} = Outbox.get(row.id)
  end
end
