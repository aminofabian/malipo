defmodule Malipo.Rails.DarajaTest do
  use ExUnit.Case, async: false

  alias Malipo.Rails.Daraja
  alias Malipo.Rails.Failure
  alias Malipo.Rails.TokenCache

  setup do
    bypass = Bypass.open()
    base = "http://127.0.0.1:#{bypass.port}"

    creds = %{
      "consumerKey" => "key",
      "consumerSecret" => "secret",
      "shortcode" => "4094529",
      "passkey" => "live-passkey-not-sandbox",
      "environment" => "sandbox",
      "shortcodeType" => "paybill",
      "base_url" => base
    }

    # Drop any cached OAuth from prior tests.
    TokenCache.invalidate({"key", base})

    {:ok, bypass: bypass, creds: creds, base: base}
  end

  defp fixture(name) do
    Path.join([
      File.cwd!(),
      "test/malipo/rails/daraja/fixtures",
      name
    ])
    |> File.read!()
  end

  defp stub_oauth(bypass) do
    Bypass.expect(bypass, "GET", "/oauth/v1/generate", fn conn ->
      assert conn.query_string =~ "grant_type=client_credentials"
      [auth] = Plug.Conn.get_req_header(conn, "authorization")
      assert String.starts_with?(auth, "Basic ")

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"access_token":"tok_test","expires_in":3599}))
    end)
  end

  test "validate/1 succeeds when STK probe accepts the password", %{bypass: bypass, creds: creds} do
    stub_oauth(bypass)

    Bypass.expect(bypass, "POST", "/mpesa/stkpushquery/v1/query", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      assert payload["BusinessShortCode"] == "4094529"
      assert is_binary(payload["Password"])
      assert String.starts_with?(payload["CheckoutRequestID"], "ws_CO_malipo_probe_")

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, fixture("stk_query_probe_ok.json"))
    end)

    assert :ok = Daraja.validate(creds)
  end

  test "validate/1 fails on Wrong credentials passkey probe", %{bypass: bypass, creds: creds} do
    stub_oauth(bypass)

    Bypass.expect(bypass, "POST", "/mpesa/stkpushquery/v1/query", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, fixture("stk_query_probe_bad_passkey.json"))
    end)

    assert {:error, %Failure{kind: :bad_passkey}} = Daraja.validate(creds)
  end

  test "push/2 returns checkout id on accept", %{bypass: bypass, creds: creds} do
    stub_oauth(bypass)

    Bypass.expect(bypass, "POST", "/mpesa/stkpush/v1/processrequest", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      assert payload["Amount"] == 1450
      assert payload["PartyA"] == "254712345678"
      assert payload["PhoneNumber"] == "254712345678"
      assert payload["BusinessShortCode"] == "4094529"
      assert payload["TransactionType"] == "CustomerPayBillOnline"
      assert payload["CallBackURL"] =~ "/webhooks/daraja/stk"
      assert payload["AccountReference"] == "Till3"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, fixture("stk_push_accepted.json"))
    end)

    assert {:ok, result} =
             Daraja.push(creds, %{
               amount: Decimal.new("1450.00"),
               phone: "0712345678",
               account_reference: "Till 3",
               transaction_desc: "Palmart sale",
               callback_url: "https://kiosk.ke"
             })

    assert result.checkout_request_id == "ws_CO_190920261234_ABC"
    assert result.merchant_request_id == "29115-34620561-1"
  end

  test "push/2 keeps a long bank account reference intact", %{bypass: bypass, creds: creds} do
    stub_oauth(bypass)

    Bypass.expect(bypass, "POST", "/mpesa/stkpush/v1/processrequest", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      # A 13-digit account ending in zeros must reach Daraja whole — truncating
      # it (e.g. to 12) pays the wrong account.
      assert payload["AccountReference"] == "0112345678900"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, fixture("stk_push_accepted.json"))
    end)

    assert {:ok, _result} =
             Daraja.push(creds, %{
               amount: Decimal.new("1.00"),
               phone: "0712345678",
               account_reference: "0112345678900",
               transaction_desc: "Bank settlement",
               callback_url: "https://kiosk.ke"
             })
  end

  test "push/2 honours request party_b for custody collection", %{bypass: bypass, creds: creds} do
    stub_oauth(bypass)

    Bypass.expect(bypass, "POST", "/mpesa/stkpush/v1/processrequest", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      assert payload["PartyB"] == "5738421"
      assert payload["TransactionType"] == "CustomerBuyGoodsOnline"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, fixture("stk_push_accepted.json"))
    end)

    assert {:ok, _} =
             Daraja.push(creds, %{
               amount: 10,
               phone: "254712345678",
               account_reference: "Order1",
               transaction_desc: "Sale",
               callback_url: "https://kiosk.ke",
               party_b: "5738421",
               transaction_type: "CustomerBuyGoodsOnline"
             })
  end

  test "push/2 classifies Wrong credentials", %{bypass: bypass, creds: creds} do
    stub_oauth(bypass)

    Bypass.expect(bypass, "POST", "/mpesa/stkpush/v1/processrequest", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(400, fixture("stk_push_wrong_credentials.json"))
    end)

    assert {:error, %Failure{kind: :bad_passkey}} =
             Daraja.push(creds, %{
               amount: 1,
               phone: "254712345678",
               account_reference: "Test",
               transaction_desc: "Probe",
               callback_url: "https://kiosk.ke"
             })
  end

  test "query/2 success returns receipt", %{bypass: bypass, creds: creds} do
    stub_oauth(bypass)

    Bypass.expect(bypass, "POST", "/mpesa/stkpushquery/v1/query", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, fixture("stk_query_success.json"))
    end)

    assert {:ok, result} = Daraja.query(creds, "ws_CO_190920261234_ABC")
    assert result.outcome == :success
    assert result.receipt == "SJH4K2LM9P"
    assert Decimal.eq?(result.amount, Decimal.new("1450.00"))
  end

  test "query/2 cancelled returns classified failure", %{bypass: bypass, creds: creds} do
    stub_oauth(bypass)

    Bypass.expect(bypass, "POST", "/mpesa/stkpushquery/v1/query", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, fixture("stk_query_cancelled.json"))
    end)

    assert {:error, %Failure{kind: :subscriber_cancelled, provider_code: "1032"}} =
             Daraja.query(creds, "ws_CO_190920261234_ABC")
  end

  test "rejects sandbox passkey on production shortcode" do
    creds = %{
      consumer_key: "k",
      consumer_secret: "s",
      shortcode: "4094529",
      passkey: "bfb279f9aa9bdbcf158e97dd71a467cd2e0c893059b10f78e6b72ada1ed2c919",
      environment: "production"
    }

    assert {:error, %Failure{kind: :bad_passkey}} = Daraja.validate(creds)
  end
end
