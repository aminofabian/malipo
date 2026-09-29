defmodule Malipo.AdminTest do
  use Malipo.DataCase, async: true

  alias Malipo.Admin
  alias Malipo.ConnectAccounts
  alias Malipo.Intents
  alias Malipo.Merchants
  alias Malipo.Till

  defp fixture(name) do
    Path.join([File.cwd!(), "test/malipo/rails/daraja/fixtures", name]) |> File.read!()
  end

  defp settle(business_id, key, amount, receipt) do
    {:ok, intent} =
      Intents.create(%{
        business_id: business_id,
        idempotency_key: key,
        amount: amount,
        payer_msisdn: "0712345678"
      })

    {:ok, prompted} = Intents.mark_prompted(intent, %{checkout_request_id: "ws_" <> key})
    {:ok, settled} = Intents.mark_settled(prompted, %{receipt: receipt})
    settled
  end

  test "overview rolls up accounts, intents, till receipts and outbox" do
    {:ok, account} =
      ConnectAccounts.register(%{"email" => "shop@example.com", "password" => "secret123"})

    settle(account.business_id, "admin-overview-1", "1500.00", "ADMINRCPT1")

    {:ok, _receipt, :unmatched} = Till.ingest_confirmation(fixture("c2b_confirmation.json"))

    overview = Admin.overview()

    assert overview.accounts.total == 1
    assert overview.intents.total == 1
    assert overview.intents.settled == 1
    assert Decimal.eq?(overview.intents.settled_volume, Decimal.new("1500.00"))
    assert overview.till.total == 1
    assert overview.till.unmatched == 1
    assert overview.outbox.pending >= 1
  end

  test "list_accounts enriches accounts with destination, key and intent rollup" do
    {:ok, account} =
      ConnectAccounts.register(%{"email" => "merchant@example.com", "password" => "secret123"})

    business_id = account.business_id

    {:ok, _dest} =
      Merchants.put_destination(business_id, %{"kind" => "till", "till_number" => "5738421"})

    {:ok, _} = Merchants.confirm_destination(business_id)
    {:ok, _} = Merchants.provision_keys(business_id)

    settle(business_id, "admin-accounts-1", "250.00", "ACCTRCPT1")

    assert [row] = Admin.list_accounts()
    assert row.account.email == "merchant@example.com"
    assert row.destination.till_number == "5738421"
    assert row.key.client_id =~ "pk_live_"
    assert row.intent_count == 1
    assert row.settled_count == 1
    assert Decimal.eq?(row.settled_volume, Decimal.new("250.00"))
  end

  test "list_transactions merges intents and receipts, and filters by kind" do
    settle("biz_tx", "admin-tx-1", "999.00", "ADMINTX001")
    {:ok, _receipt, :unmatched} = Till.ingest_confirmation(fixture("c2b_confirmation.json"))

    all = Admin.list_transactions(50, "all")
    assert Enum.any?(all, &(&1.kind == "stk" and &1.reference == "ADMINTX001"))
    assert Enum.any?(all, &(&1.kind == "c2b" and &1.reference == "SJH4K2LM9P"))

    stk = Admin.list_transactions(50, "stk")
    assert Enum.all?(stk, &(&1.kind == "stk"))
    assert Enum.all?(stk, &is_binary(&1.intent_id))

    c2b = Admin.list_transactions(50, "c2b")
    assert Enum.all?(c2b, &(&1.kind == "c2b"))
  end

  test "intent_detail returns attempts, events and the matched receipt" do
    intent = settle("biz_detail", "admin-detail-1", "500.00", "DETAILRCPT")

    assert {:ok, detail} = Admin.intent_detail(intent.id)
    assert detail.intent.id == intent.id
    assert [attempt] = detail.attempts
    assert attempt.attempt_number == 1
    assert Enum.any?(detail.events, &(&1.event == "intent.settled"))
    assert detail.receipt == nil

    assert {:error, :not_found} = Admin.intent_detail(Ecto.UUID.generate())
  end
end
