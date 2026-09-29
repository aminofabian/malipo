defmodule Malipo.MerchantsTest do
  use Malipo.DataCase, async: true

  alias Malipo.Merchants
  alias Malipo.Merchants.ApiKey

  test "destination upsert + confirm + provision keys (show once)" do
    assert {:ok, dest} =
             Merchants.put_destination("biz_m1", %{
               "kind" => "till",
               "till_number" => "5738421"
             })

    assert dest.kind == "till"
    assert dest.till_number == "5738421"
    assert dest.verified == false
    assert dest.activated == false
    refute Merchants.collections_allowed?("biz_m1")

    assert {:ok, confirmed} = Merchants.confirm_destination("biz_m1")
    assert confirmed.verified
    assert confirmed.activated
    assert confirmed.active
    assert Merchants.collections_allowed?("biz_m1")

    assert {:ok, second} =
             Merchants.create_destination("biz_m1", %{
               "kind" => "till",
               "till_number" => "600100"
             })

    refute second.active
    assert {:ok, _} = Merchants.confirm_destination("biz_m1", second.id)
    assert Merchants.get_active_destination("biz_m1").till_number == "600100"
    assert length(Merchants.list_for_business("biz_m1")) == 2

    assert {:ok, revealed} = Merchants.provision_keys("biz_m1")
    assert String.starts_with?(revealed.client_id, "pk_live_")
    assert String.starts_with?(revealed.client_secret, "sk_live_")
    assert String.starts_with?(revealed.webhook_secret, "whsec_")

    key = Merchants.get_active_key("biz_m1")
    assert %ApiKey{client_id: client_id} = key
    assert client_id == revealed.client_id
    refute is_nil(key.client_secret_hash)

    assert {:ok, "biz_m1"} = Merchants.authenticate(revealed.client_id, revealed.client_secret)
    assert {:ok, "biz_m1"} = Merchants.authenticate_secret(revealed.client_secret)
    assert {:error, :unauthorized} = Merchants.authenticate(revealed.client_id, "wrong")
    assert {:error, :unauthorized} = Merchants.authenticate_secret("sk_live_nope")

    # Rotate — same client_id, new secret; old secret dies
    assert {:ok, rotated} = Merchants.provision_keys("biz_m1")
    assert rotated.client_id == revealed.client_id
    assert rotated.client_secret != revealed.client_secret
    assert {:error, :unauthorized} =
             Merchants.authenticate(revealed.client_id, revealed.client_secret)

    assert {:ok, "biz_m1"} = Merchants.authenticate(rotated.client_id, rotated.client_secret)
    assert {:error, :unauthorized} = Merchants.authenticate_secret(revealed.client_secret)
    assert {:ok, "biz_m1"} = Merchants.authenticate_secret(rotated.client_secret)
  end

  test "cannot provision without confirm" do
    assert {:ok, _} =
             Merchants.put_destination("biz_m2", %{
               "kind" => "paybill",
               "paybill_number" => "522522",
               "account_number" => "SHOP1"
             })

    assert {:error, :destination_not_ready} = Merchants.provision_keys("biz_m2")
  end

  test "bank destination uses Lipa Na M-Pesa paybill + account" do
    assert {:ok, dest} =
             Merchants.put_destination("biz_bank", %{
               "kind" => "bank",
               "bank_id" => "equity",
               "paybill_number" => "247247",
               "account_number" => "0123456789",
               "display_name" => "Equity Bank · Acc 0123456789"
             })

    assert dest.kind == "bank"
    assert dest.bank_id == "equity"
    assert dest.paybill_number == "247247"
    assert dest.account_number == "0123456789"
    assert dest.till_number == nil
  end
end
