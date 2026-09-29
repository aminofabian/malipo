defmodule MalipoWeb.MerchantControllerTest do
  use MalipoWeb.ConnCase, async: true

  alias Malipo.Merchants

  defp settle(business_id, key, amount, receipt) do
    {:ok, intent} =
      Malipo.Intents.create(%{
        business_id: business_id,
        idempotency_key: key,
        amount: amount,
        payer_msisdn: "0712345678"
      })

    {:ok, prompted} = Malipo.Intents.mark_prompted(intent, %{checkout_request_id: "ws_" <> key})
    {:ok, settled} = Malipo.Intents.mark_settled(prompted, %{receipt: receipt})
    settled
  end

  test "provision flow via internal API", %{conn: conn} do
    put(conn, ~p"/internal/v1/merchants/biz_api_m/destination", %{
      "kind" => "till",
      "till_number" => "1234567"
    })
    |> json_response(201)

    post(conn, ~p"/internal/v1/merchants/biz_api_m/confirm", %{})
    |> json_response(200)

    body =
      post(conn, ~p"/internal/v1/merchants/biz_api_m/keys", %{})
      |> json_response(201)

    assert String.starts_with?(body["client_id"], "pk_live_")
    assert String.starts_with?(body["client_secret"], "sk_live_")
    assert String.starts_with?(body["webhook_secret"], "whsec_")

    show =
      get(conn, ~p"/internal/v1/merchants/biz_api_m")
      |> json_response(200)

    assert show["client_id"] == body["client_id"]
    assert show["collections_allowed"] == true
    # secrets never on GET
    refute Map.has_key?(show, "client_secret")

    put(conn, ~p"/internal/v1/merchants/biz_api_m/webhook", %{
      "url" => "https://example.com/hooks/malipo"
    })
    |> json_response(200)

    show2 =
      get(conn, ~p"/internal/v1/merchants/biz_api_m")
      |> json_response(200)

    assert show2["webhook_url"] == "https://example.com/hooks/malipo"
  end

  test "intents snapshot the active destination for attribution" do
    {:ok, dest} =
      Merchants.put_destination("biz_attr", %{"kind" => "till", "till_number" => "7654321"})

    {:ok, _} = Merchants.confirm_destination("biz_attr")

    settled = settle("biz_attr", "attr-key-1", "100.00", "ATTRRCPT1")

    assert settled.context["settlement_destination_id"] == dest.id
  end

  test "summary totals settled payments per destination", %{conn: conn} do
    {:ok, dest} =
      Merchants.put_destination("biz_sum", %{"kind" => "till", "till_number" => "1234567"})

    {:ok, _} = Merchants.confirm_destination("biz_sum")

    settle("biz_sum", "summary-key-1", "100.00", "SUMRCPT1")
    settle("biz_sum", "summary-key-2", "250.00", "SUMRCPT2")

    body = get(conn, ~p"/internal/v1/merchants/biz_sum/summary") |> json_response(200)

    assert body["received_count"] == 2
    assert body["received_total"] == "350.00"

    assert [%{"destination_id" => id, "count" => 2, "total" => "350.00"}] =
             body["by_destination"]

    assert id == dest.id
  end

  test "summary is empty before any settlement", %{conn: conn} do
    body = get(conn, ~p"/internal/v1/merchants/biz_empty/summary") |> json_response(200)

    assert body["received_count"] == 0
    assert body["received_total"] == "0"
    assert body["by_destination"] == []
  end
end
