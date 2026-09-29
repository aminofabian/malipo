defmodule MalipoWeb.Admin.TransactionsLiveTest do
  use MalipoWeb.ConnCase, async: true

  alias Malipo.Intents
  alias Malipo.Till

  defp fixture(name) do
    Path.join([File.cwd!(), "test/malipo/rails/daraja/fixtures", name]) |> File.read!()
  end

  test "shows STK intents and C2B receipts, and filters by type", %{conn: conn} do
    {:ok, intent} =
      Intents.create(%{
        business_id: "biz_tx_live",
        idempotency_key: "tx-live-1",
        amount: "999.00",
        payer_msisdn: "0712345678"
      })

    {:ok, prompted} = Intents.mark_prompted(intent, %{checkout_request_id: "ws_tx_live"})
    {:ok, _} = Intents.mark_settled(prompted, %{receipt: "TXLIVE001"})

    {:ok, _receipt, :unmatched} = Till.ingest_confirmation(fixture("c2b_confirmation.json"))

    {:ok, view, html} = conn |> log_in_admin() |> live(~p"/admin/transactions")

    assert html =~ "TXLIVE001"
    assert html =~ "SJH4K2LM9P"

    html =
      view
      |> element(~s{button[phx-value-filter="c2b"]})
      |> render_click()

    assert html =~ "SJH4K2LM9P"
    refute html =~ "TXLIVE001"
  end

  test "dashboard summarises the same data", %{conn: conn} do
    {:ok, _receipt, :unmatched} = Till.ingest_confirmation(fixture("c2b_confirmation.json"))

    {:ok, _view, html} = conn |> log_in_admin() |> live(~p"/admin")

    assert html =~ "Settled volume (24h)"
    assert html =~ "Connect accounts"
    assert html =~ "Till receipts"
  end
end
