defmodule MalipoWeb.IntentControllerTest do
  use MalipoWeb.ConnCase, async: false

  import Ecto.Query

  alias Malipo.Intents.Attempt
  alias Malipo.Rails.TokenCache
  alias Malipo.Repo

  setup do
    bypass = Bypass.open()
    base = "http://127.0.0.1:#{bypass.port}"

    previous = Application.get_env(:malipo, :daraja, [])

    Application.put_env(:malipo, :daraja,
      consumer_key: "key",
      consumer_secret: "secret",
      shortcode: "4094529",
      passkey: "live-passkey-not-sandbox",
      environment: "sandbox",
      shortcode_type: "paybill",
      base_url: base,
      callback_base: "https://kiosk.ke"
    )

    TokenCache.invalidate({"key", base})

    on_exit(fn -> Application.put_env(:malipo, :daraja, previous) end)

    {:ok, bypass: bypass, base: base}
  end

  defp fixture(name) do
    Path.join([File.cwd!(), "test/malipo/rails/daraja/fixtures", name]) |> File.read!()
  end

  defp stub_oauth(bypass) do
    Bypass.stub(bypass, "GET", "/oauth/v1/generate", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"access_token":"tok_test","expires_in":3599}))
    end)
  end

  defp expect_stk(bypass, checkout_id) do
    stub_oauth(bypass)

    Bypass.expect(bypass, "POST", "/mpesa/stkpush/v1/processrequest", fn conn ->
      resp =
        fixture("stk_push_accepted.json")
        |> String.replace("ws_CO_190920261234_ABC", checkout_id)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, resp)
    end)
  end

  defp intent_body(overrides \\ %{}) do
    Map.merge(
      %{
        "idempotency_key" => "pos:sale:api-test-001:attempt:1",
        "business_id" => "biz_api",
        "amount" => "1450.00",
        "currency" => "KES",
        "payer_msisdn" => "0712345678",
        "context" => %{"type" => "POS_PAYMENT", "id" => "sale_api"},
        "on_settled" => %{"topic" => "palmart.settlements"}
      },
      overrides
    )
  end

  test "POST /internal/v1/intents creates and pushes", %{conn: conn, bypass: bypass} do
    expect_stk(bypass, "ws_CO_190920261234_ABC")

    body =
      post(conn, ~p"/internal/v1/intents", intent_body())
      |> json_response(201)

    assert body["status"] == "prompted"
    assert body["replay"] == false
    assert body["checkout_request_id"] == "ws_CO_190920261234_ABC"
    assert body["context"]["on_settled"]["topic"] == "palmart.settlements"
  end

  test "POST /internal/v1/intents replays without a second push", %{conn: conn, bypass: bypass} do
    expect_stk(bypass, "ws_CO_190920261234_ABC")
    body = intent_body(%{"idempotency_key" => "pos:sale:api-replay:attempt:1"})

    assert %{"id" => id, "replay" => false} =
             post(conn, ~p"/internal/v1/intents", body) |> json_response(201)

    assert %{"id" => ^id, "status" => "prompted", "replay" => true} =
             post(build_conn(), ~p"/internal/v1/intents", body) |> json_response(200)
  end

  test "GET /internal/v1/intents/:id", %{conn: conn, bypass: bypass} do
    expect_stk(bypass, "ws_CO_GET")

    %{"id" => id} =
      post(conn, ~p"/internal/v1/intents", intent_body(%{"idempotency_key" => "get-1-xxxxxxxx"}))
      |> json_response(201)

    assert %{"id" => ^id, "status" => "prompted"} =
             get(build_conn(), ~p"/internal/v1/intents/#{id}") |> json_response(200)
  end

  test "POST /internal/v1/intents/:id/resend adds another attempt", %{conn: conn, bypass: bypass} do
    stub_oauth(bypass)
    agent = start_supervised!({Agent, fn -> 0 end})

    Bypass.expect(bypass, "POST", "/mpesa/stkpush/v1/processrequest", fn conn ->
      n = Agent.get_and_update(agent, fn c -> {c + 1, c + 1} end)
      checkout = if n == 1, do: "ws_CO_FIRST", else: "ws_CO_RESEND"

      resp =
        fixture("stk_push_accepted.json")
        |> String.replace("ws_CO_190920261234_ABC", checkout)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, resp)
    end)

    %{"id" => id} =
      post(conn, ~p"/internal/v1/intents", intent_body(%{"idempotency_key" => "resend-1-xxxxxx"}))
      |> json_response(201)

    assert %{"status" => "prompted", "checkout_request_id" => "ws_CO_RESEND"} =
             post(build_conn(), ~p"/internal/v1/intents/#{id}/resend", %{})
             |> json_response(200)

    assert length(Repo.all(from(a in Attempt, where: a.intent_id == ^id))) == 2
  end

  test "POST /internal/v1/till-awaits opens a Buy Goods wait window", %{conn: conn} do
    body =
      post(conn, ~p"/internal/v1/till-awaits", %{
        "business_id" => "biz_till_api",
        "amount" => "250.00",
        "payer_msisdn" => "0712345678",
        "context" => %{"type" => "POS_PAYMENT", "await_owner_id" => "till_3"}
      })
      |> json_response(201)

    assert body["status"] == "prompted"
    assert body["business_id"] == "biz_till_api"
    assert String.starts_with?(body["checkout_request_id"], "till-await-")
    assert body["replay"] == false

    # Idempotent replay
    assert %{"id" => id, "replay" => true} =
             post(conn, ~p"/internal/v1/till-awaits", %{
               "business_id" => "biz_till_api",
               "amount" => "250.00",
               "idempotency_key" => body["idempotency_key"],
               "payer_msisdn" => "0712345678"
             })
             |> json_response(200)

    assert id == body["id"]
  end

  test "POST /internal/v1/till-awaits rejects non-positive amount", %{conn: conn} do
    assert json_response(
             post(conn, ~p"/internal/v1/till-awaits", %{
               "business_id" => "biz_till_api",
               "amount" => "0"
             }),
             422
           )["error"] == "invalid_amount"
  end

  test "service token rejects unauthorized when configured", %{conn: conn} do
    previous = Application.get_env(:malipo, :service_token)
    Application.put_env(:malipo, :service_token, "secret-token")
    on_exit(fn -> Application.put_env(:malipo, :service_token, previous) end)

    assert json_response(post(conn, ~p"/internal/v1/intents", intent_body()), 401)["error"] ==
             "unauthorized"
  end

  test "create_and_push without credentials returns 503", %{conn: conn} do
    Application.put_env(:malipo, :daraja, [])

    assert json_response(
             post(conn, ~p"/internal/v1/intents", intent_body(%{"idempotency_key" => "no-creds-xxxxx"})),
             503
           )["error"] == "credentials_missing"
  end
end
