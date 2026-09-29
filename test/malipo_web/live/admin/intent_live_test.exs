defmodule MalipoWeb.Admin.IntentLiveTest do
  use MalipoWeb.ConnCase, async: true

  alias Malipo.Intents

  test "shows the intent lifecycle, attempts and events", %{conn: conn} do
    {:ok, intent} =
      Intents.create(%{
        business_id: "biz_detail",
        idempotency_key: "detail-key-1",
        amount: "1234.00",
        payer_msisdn: "0712345678"
      })

    {:ok, prompted} = Intents.mark_prompted(intent, %{checkout_request_id: "ws_detail_1"})
    {:ok, settled} = Intents.mark_settled(prompted, %{receipt: "DETAILRCPT1"})

    {:ok, _view, html} =
      conn |> log_in_admin() |> live(~p"/admin/intents/#{settled.id}")

    assert html =~ "Back to intents"
    assert html =~ "DETAILRCPT1"
    assert html =~ "ws_detail_1"
    assert html =~ "biz_detail"
    assert html =~ "Attempts"
    assert html =~ "intent.settled"
  end

  test "an unknown intent redirects back to the list", %{conn: conn} do
    assert {:error, {_kind, %{to: "/admin/intents"}}} =
             conn |> log_in_admin() |> live(~p"/admin/intents/#{Ecto.UUID.generate()}")
  end

  test "the intents list links through to the inspector", %{conn: conn} do
    {:ok, intent} =
      Intents.create(%{
        business_id: "biz_link",
        idempotency_key: "link-key-1",
        amount: "10.00",
        payer_msisdn: "0712345678"
      })

    {:ok, _view, html} = conn |> log_in_admin() |> live(~p"/admin/intents")

    assert html =~ ~s{href="/admin/intents/#{intent.id}"}
  end
end
