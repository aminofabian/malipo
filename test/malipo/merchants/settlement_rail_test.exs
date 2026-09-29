defmodule Malipo.Merchants.SettlementRailTest do
  use ExUnit.Case, async: true

  alias Malipo.Merchants.Destination
  alias Malipo.Merchants.SettlementRail

  test "till destination maps to buy goods PartyB" do
    dest = %Destination{
      kind: "till",
      till_number: "5738421",
      verified: true,
      activated: true,
      active: true
    }

    assert {:ok, %{party_b: "5738421", transaction_type: "CustomerBuyGoodsOnline"}} =
             SettlementRail.stk_push_overrides(dest)
  end

  test "paybill destination maps PartyB and account reference" do
    dest = %Destination{
      kind: "paybill",
      paybill_number: "400200",
      account_number: "ACC001",
      verified: true,
      activated: true,
      active: true
    }

    assert {:ok, overrides} = SettlementRail.stk_push_overrides(dest)
    assert overrides.party_b == "400200"
    assert overrides.transaction_type == "CustomerPayBillOnline"
    assert overrides.account_reference == "ACC001"
  end

  test "context party_b for Palmart-style intents" do
    assert {:ok, %{party_b: "5738421"}} =
             SettlementRail.overrides_for_push(%{"party_b" => "5738421"}, "biz_java")
  end

  test "settlement_destination map on context" do
    assert {:ok, %{party_b: "5738421"}} =
             SettlementRail.overrides_for_push(
               %{
                 "settlement_destination" => %{
                   "kind" => "till",
                   "till_number" => "5738421"
                 }
               },
               "biz_java"
             )
  end
end
