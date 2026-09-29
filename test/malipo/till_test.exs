defmodule Malipo.TillTest do
  use Malipo.DataCase, async: false

  alias Malipo.Intents
  alias Malipo.Outbox.Event, as: OutboxEvent
  alias Malipo.Till
  alias Malipo.Till.Receipt

  defp fixture(name) do
    Path.join([File.cwd!(), "test/malipo/rails/daraja/fixtures", name]) |> File.read!()
  end

  test "ingest_confirmation stores unmatched receipt and writes outbox" do
    body = fixture("c2b_confirmation.json")

    assert {:ok, %Receipt{status: "unmatched", trans_id: "SJH4K2LM9P"} = receipt, :unmatched} =
             Till.ingest_confirmation(body)

    assert Decimal.eq?(receipt.amount, Decimal.new("100.00"))
    assert receipt.payer_msisdn == "254712345678"
    assert receipt.bill_ref == "sale_wh_c2b"
    assert receipt.shortcode == "4094529"

    assert [%OutboxEvent{event: "till_receipt.unmatched"}] = Repo.all(OutboxEvent)

    assert {:ok, ^receipt, :duplicate} = Till.ingest_confirmation(body)
    assert [_] = Repo.all(Receipt)
  end

  test "ingest_confirmation matches prompted intent by BillRefNumber" do
    assert {:ok, intent} =
             Intents.create(%{
               business_id: "biz_till",
               idempotency_key: "sale_wh_c2b",
               amount: "100.00",
               payer_msisdn: "0712345678",
               context: %{"type" => "POS_PAYMENT", "id" => "sale_wh_c2b"}
             })

    assert {:ok, prompted} =
             Intents.mark_prompted(intent, %{checkout_request_id: "ws_CO_TILL_1"})

    body = fixture("c2b_confirmation.json")

    assert {:ok, %Receipt{status: "matched", matched_intent_id: intent_id}, :matched} =
             Till.ingest_confirmation(body)

    assert intent_id == prompted.id
    settled = Intents.get!(prompted.id)
    assert settled.status == "settled"
    assert settled.receipt == "SJH4K2LM9P"

    # Matched path emits intent.settled, not till_receipt.unmatched.
    events = Repo.all(OutboxEvent) |> Enum.map(& &1.event)
    assert "intent.settled" in events
    refute "till_receipt.unmatched" in events
  end

  test "open_till_await late-binds an unmatched receipt" do
    assert {:ok, %Receipt{status: "unmatched"} = receipt, :unmatched} =
             Till.ingest_confirmation(fixture("c2b_confirmation.json"))

    # Fixture amount 100.00 / phone 254712345678
    assert {:ok, settled} =
             Intents.open_till_await(%{
               "business_id" => "biz_late",
               "amount" => "100.00",
               "payer_msisdn" => "0712345678",
               "idempotency_key" => "till-late-bind-001",
               "context" => %{"type" => "POS_PAYMENT", "await_owner_id" => "t1"}
             })

    assert settled.status == "settled"
    assert settled.receipt == receipt.trans_id
    assert Repo.get!(Receipt, receipt.id).status == "matched"
  end

  test "open_till_await replaces prior await for same owner" do
    assert {:ok, first} =
             Intents.open_till_await(%{
               "business_id" => "biz_replace",
               "amount" => "50.00",
               "idempotency_key" => "till-replace-a-xxxxx",
               "context" => %{"await_owner_id" => "register_1"}
             })

    assert first.status == "prompted"

    assert {:ok, second} =
             Intents.open_till_await(%{
               "business_id" => "biz_replace",
               "amount" => "75.00",
               "idempotency_key" => "till-replace-b-xxxxx",
               "context" => %{"await_owner_id" => "register_1"}
             })

    assert second.status == "prompted"
    assert Intents.get!(first.id).status == "failed"
    assert Intents.get!(first.id).failure_kind == "replaced"
  end
end
