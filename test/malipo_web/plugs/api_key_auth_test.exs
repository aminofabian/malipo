defmodule MalipoWeb.Plugs.ApiKeyAuthTest do
  use MalipoWeb.ConnCase, async: true

  import Plug.Conn

  alias Malipo.Merchants
  alias MalipoWeb.Plugs.ApiKeyAuth

  defp provision_live(business_id) do
    {:ok, _} =
      Merchants.put_destination(business_id, %{"kind" => "till", "till_number" => "5738421"})

    {:ok, _} = Merchants.confirm_destination(business_id)
    {:ok, keys} = Merchants.provision_keys(business_id)
    keys
  end

  defp call(conn, opts, auth) do
    conn
    |> put_req_header("authorization", auth)
    |> ApiKeyAuth.call(opts)
  end

  test "a live key passes where live is allowed and assigns business_id + mode", %{conn: conn} do
    keys = provision_live("biz_auth_live")

    conn = call(conn, ApiKeyAuth.init([]), "Bearer #{keys.client_secret}")

    refute conn.halted
    assert conn.assigns.business_id == "biz_auth_live"
    assert conn.assigns.mode == "live"
  end

  test "a test key is rejected where only live is allowed", %{conn: conn} do
    {:ok, keys} = Merchants.provision_keys("biz_auth_test", "test")

    conn = call(conn, ApiKeyAuth.init([]), "Bearer #{keys.client_secret}")

    assert conn.status == 403
    assert conn.halted
    assert conn.assigns[:mode] == nil

    body = Jason.decode!(conn.resp_body)
    assert body["error"] == "mode_not_allowed"
    assert body["key_mode"] == "test"
  end

  test "a live key is rejected where only test is allowed", %{conn: conn} do
    keys = provision_live("biz_auth_live2")

    conn = call(conn, ApiKeyAuth.init(allow: ["test"]), "Bearer #{keys.client_secret}")

    assert conn.status == 403
    assert Jason.decode!(conn.resp_body)["key_mode"] == "live"
  end

  test "a test key passes where test is allowed", %{conn: conn} do
    {:ok, keys} = Merchants.provision_keys("biz_auth_test2", "test")

    conn = call(conn, ApiKeyAuth.init(allow: ["test"]), "Bearer #{keys.client_secret}")

    refute conn.halted
    assert conn.assigns.mode == "test"
  end

  test "basic auth carries the mode too", %{conn: conn} do
    {:ok, keys} = Merchants.provision_keys("biz_auth_test3", "test")
    token = Base.encode64("#{keys.client_id}:#{keys.client_secret}")

    conn = call(conn, ApiKeyAuth.init([]), "Basic #{token}")

    assert conn.status == 403
    assert Jason.decode!(conn.resp_body)["key_mode"] == "test"
  end

  test "missing auth is 401", %{conn: conn} do
    conn = ApiKeyAuth.call(conn, ApiKeyAuth.init([]))

    assert conn.status == 401
    assert Jason.decode!(conn.resp_body) == %{"error" => "unauthorized"}
  end
end
