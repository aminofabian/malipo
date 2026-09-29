defmodule Malipo.FeesTest do
  use Malipo.DataCase, async: false

  alias Malipo.Fees
  alias Malipo.Intents
  alias Malipo.Outbox.Event, as: OutboxEvent
  alias Malipo.Repo

  describe "quote/1" do
    test "maps amounts to the shipped schedule" do
      assert {:ok, %{fee: fee, net: net}} = Fees.quote(1)
      assert Decimal.eq?(fee, Decimal.new(0))
      assert Decimal.eq?(net, Decimal.new(1))

      assert {:ok, %{fee: fee, net: net}} = Fees.quote(1000)
      assert Decimal.eq?(fee, Decimal.new(15))
      assert Decimal.eq?(net, Decimal.new(985))

      assert {:ok, %{fee: fee}} = Fees.quote(999_999)
      assert Decimal.eq?(fee, Decimal.new(320))
    end

    test "band boundaries are inclusive on both ends" do
      assert {:ok, %{fee: fee}} = Fees.quote(49)
      assert Decimal.eq?(fee, Decimal.new(1))

      assert {:ok, %{fee: fee}} = Fees.quote(50)
      assert Decimal.eq?(fee, Decimal.new(6))
    end

    test "amounts below the first band are fee-free" do
      assert {:ok, %{fee: fee, net: net}} = Fees.quote(0)
      assert Decimal.eq?(fee, Decimal.new(0))
      assert Decimal.eq?(net, Decimal.new(0))
    end

    test "accepts strings and decimals and rejects junk" do
      assert {:ok, %{fee: fee}} = Fees.quote("1500.00")
      assert Decimal.eq?(fee, Decimal.new(20))

      assert {:ok, %{fee: fee}} = Fees.quote(Decimal.new("2500"))
      assert Decimal.eq?(fee, Decimal.new(25))

      assert {:error, :invalid_amount} = Fees.quote("nope")
    end
  end

  describe "schedule editing" do
    test "replace_bands swaps the whole schedule" do
      assert {:ok, bands} =
               Fees.replace_bands([
                 %{amount_from: 1, amount_to: 99, fee: 2},
                 %{amount_from: 100, amount_to: 999, fee: 9}
               ])

      assert length(bands) == 2
      assert {:ok, %{fee: fee}} = Fees.quote(50)
      assert Decimal.eq?(fee, Decimal.new(2))
    end

    test "replace_bands rejects invalid ranges and keeps the schedule" do
      assert length(Fees.list_bands()) == 20

      assert {:error, _} =
               Fees.replace_bands([%{amount_from: 100, amount_to: 10, fee: 1}])

      assert length(Fees.list_bands()) == 20
    end
  end

  describe "configuration" do
    test "update_config stores rates and fee destination" do
      assert {:ok, row} =
               Fees.update_config(%{
                 "sms_rate" => 90,
                 "whatsapp_rate" => 70,
                 "fee_destination_kind" => "till",
                 "fee_destination_till" => "5738421"
               })

      assert row.sms_rate == 90

      assert %{kind: "till", till_number: "5738421"} = Fees.destination()
    end

    test "destination is nil when unset" do
      assert Fees.destination() == nil
    end

    test "public_view exposes rates and bands without secrets" do
      view = Fees.public_view()
      assert view["currency"] == "KES"
      assert view["sms_rate"] == "0.80"
      assert view["whatsapp_rate"] == "0.60"
      assert is_list(view["bands"])
      assert length(view["bands"]) == 20
    end
  end

  describe "settlement" do
    defp settle(amount, key) do
      {:ok, intent} =
        Intents.create(%{
          business_id: "biz_fee",
          idempotency_key: key,
          amount: amount,
          payer_msisdn: "0712345678",
          context: %{"type" => "POS_PAYMENT", "id" => key}
        })

      {:ok, prompted} = Intents.mark_prompted(intent, %{checkout_request_id: "ws_#{key}"})
      Intents.mark_settled(prompted, %{receipt: "RCP_#{key}"})
    end

    test "records the fee and net on the settled intent" do
      assert {:ok, settled} = settle("1450.00", "fee-settle-1")
      assert Decimal.eq?(settled.fee_amount, Decimal.new(15))
      assert Decimal.eq?(settled.net_amount, Decimal.new(1435))
    end

    test "settled outbox event carries fee, net, and destination" do
      assert {:ok, _} =
               Fees.update_config(%{
                 "fee_destination_kind" => "till",
                 "fee_destination_till" => "5738421"
               })

      assert {:ok, _settled} = settle("600.00", "fee-settle-2")

      assert [%OutboxEvent{} = row] =
               Repo.all(from e in OutboxEvent, where: e.event == "intent.settled")

      assert Decimal.eq?(Decimal.new(row.payload["fee"]), Decimal.new(10))
      assert Decimal.eq?(Decimal.new(row.payload["net"]), Decimal.new(590))
      assert %{"kind" => "till", "till_number" => "5738421"} = row.payload["fee_destination"]
    end
  end
end
