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

  test "test keys are a separate, mode-carrying set (sandbox D5 + rule 1)" do
    # Test keys are available before the destination is verified (D5)…
    assert {:ok, test_keys} = Merchants.provision_keys("biz_mode", "test")
    assert String.starts_with?(test_keys.client_id, "pk_test_")
    assert String.starts_with?(test_keys.client_secret, "sk_test_")
    assert String.starts_with?(test_keys.webhook_secret, "whsec_test_")
    assert test_keys.mode == "test"

    # …but live keys are not.
    assert {:error, :destination_not_ready} = Merchants.provision_keys("biz_mode", "live")

    # The principal carries the mode; the legacy authenticate still yields the business_id.
    assert {:ok, %{business_id: "biz_mode", mode: "test"}} =
             Merchants.principal_by_secret(test_keys.client_secret)

    assert {:ok, %{business_id: "biz_mode", mode: "test"}} =
             Merchants.principal_by_pair(test_keys.client_id, test_keys.client_secret)

    assert {:ok, "biz_mode"} = Merchants.authenticate_secret(test_keys.client_secret)

    # Rotating the test key keeps the same client_id and mode; the old secret dies.
    assert {:ok, rotated} = Merchants.provision_keys("biz_mode", "test")
    assert rotated.client_id == test_keys.client_id
    assert rotated.client_secret != test_keys.client_secret
    assert {:error, :unauthorized} = Merchants.principal_by_secret(test_keys.client_secret)

    # Live keys are a different row with a different prefix, side by side.
    assert {:ok, _} =
             Merchants.put_destination("biz_mode", %{"kind" => "till", "till_number" => "5738421"})

    assert {:ok, _} = Merchants.confirm_destination("biz_mode")
    assert {:ok, live_keys} = Merchants.provision_keys("biz_mode")
    assert live_keys.mode == "live"
    assert String.starts_with?(live_keys.client_secret, "sk_live_")

    assert Merchants.get_active_key("biz_mode").client_id == live_keys.client_id
    assert Merchants.get_active_key("biz_mode", "test").client_id == rotated.client_id
    refute Merchants.get_active_key("biz_mode", "test").client_id == live_keys.client_id
  end
end
