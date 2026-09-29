defmodule Malipo.IntentsTest do
  use Malipo.DataCase, async: true

  alias Malipo.Intents
  alias Malipo.Intents.{Attempt, Intent}
  alias Malipo.Repo

  @biz "biz_test_1"
  @key "pos:sale:01TEST:attempt:1"

  defp base_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        business_id: @biz,
        idempotency_key: @key,
        amount: "1450.00",
        payer_msisdn: "0712345678",
        context: %{"type" => "POS_PAYMENT", "id" => "sale_01TEST"}
      },
      overrides
    )
  end

  test "create reserves a pending intent and normalises MSISDN" do
    assert {:ok, %Intent{} = intent} = Intents.create(base_attrs())
    assert intent.status == "pending"
    assert intent.payer_msisdn == "254712345678"
    assert intent.rail == "daraja"
    assert Decimal.eq?(intent.amount, Decimal.new("1450.00"))
  end

  test "create replays the same idempotency key without a second row" do
    assert {:ok, first} = Intents.create(base_attrs())
    assert {:ok, second, :replay} = Intents.create(base_attrs())
    assert first.id == second.id
    assert Repo.aggregate(Intent, :count) == 1
  end

  test "create rejects invalid phones" do
    assert {:error, :invalid_phone} = Intents.create(base_attrs(%{payer_msisdn: "nope"}))
  end

  test "mark_prompted moves pending → prompted and inserts an attempt" do
    {:ok, intent} = Intents.create(base_attrs(%{idempotency_key: "prompt-1"}))

    assert {:ok, prompted} =
             Intents.mark_prompted(intent, %{
               checkout_request_id: "ws_ABC",
               merchant_request_id: "mr_1",
               response_payload: %{"ResponseCode" => "0"}
             })

    assert prompted.status == "prompted"
    assert prompted.checkout_request_id == "ws_ABC"

    attempts = Repo.all(from a in Attempt, where: a.intent_id == ^prompted.id)
    assert length(attempts) == 1
    assert hd(attempts).attempt_number == 1
    assert hd(attempts).status == "sent"
  end

  test "mark_settled is terminal and blocks further status changes" do
    {:ok, intent} = Intents.create(base_attrs(%{idempotency_key: "settle-1"}))
    {:ok, prompted} = Intents.mark_prompted(intent, %{checkout_request_id: "ws_1"})

    assert {:ok, settled} =
             Intents.mark_settled(prompted, %{receipt: "SJH4K2LM9P"})

    assert settled.status == "settled"
    assert settled.receipt == "SJH4K2LM9P"

    assert {:error, %Ecto.Changeset{}} =
             Intents.mark_failed(settled, %{
               failure_kind: "customer_declined",
               failure_message: "no"
             })
  end

  test "expired intent may still settle on a late receipt" do
    {:ok, intent} = Intents.create(base_attrs(%{idempotency_key: "late-settle-001"}))
    {:ok, prompted} = Intents.mark_prompted(intent, %{checkout_request_id: "ws_late"})
    {:ok, expired} = Intents.mark_expired(prompted)

    assert expired.status == "expired"

    assert {:ok, settled} =
             Intents.mark_settled(expired, %{receipt: "LATEOK001"})

    assert settled.status == "settled"
    assert settled.receipt == "LATEOK001"
  end

  test "duplicate receipts across intents are rejected" do
    {:ok, a} = Intents.create(base_attrs(%{idempotency_key: "dup-receipt-a"}))
    {:ok, a} = Intents.mark_prompted(a, %{checkout_request_id: "ws_a"})
    assert {:ok, _} = Intents.mark_settled(a, %{receipt: "SAME_RCPT"})

    {:ok, b} = Intents.create(base_attrs(%{idempotency_key: "dup-receipt-b"}))
    {:ok, b} = Intents.mark_prompted(b, %{checkout_request_id: "ws_b"})

    assert {:error, %Ecto.Changeset{}} =
             Intents.mark_settled(b, %{receipt: "SAME_RCPT"})
  end
end
