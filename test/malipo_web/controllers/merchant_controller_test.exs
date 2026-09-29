defmodule MalipoWeb.MerchantControllerTest do
  use MalipoWeb.ConnCase, async: true

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
end
