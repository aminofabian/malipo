defmodule MalipoWeb.Webhook.DarajaControllerTest do
  use MalipoWeb.ConnCase, async: false

  alias Malipo.Repo
  alias Malipo.Webhooks.Event

  defp fixture(name) do
    Path.join([File.cwd!(), "test/malipo/rails/daraja/fixtures", name]) |> File.read!()
  end

  defp post_json(conn, path, body) when is_binary(body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, body)
  end

  test "POST /webhooks/daraja/stk returns 200 and persists", %{conn: conn} do
    body = fixture("stk_callback_success.json")
    conn = post_json(conn, ~p"/webhooks/daraja/stk", body)

    assert response(conn, 200) == "OK"
    assert [%Event{kind: "stk", dedupe_key: "ws_CO_190920261234_ABC"}] = Repo.all(Event)
  end

  test "POST /webhooks/daraja/c2b/validation accepts", %{conn: conn} do
    conn = post_json(conn, ~p"/webhooks/daraja/c2b/validation", ~s({"TransID":"CHK123"}))

    assert json_response(conn, 200)["ResultCode"] == 0
    assert [%Event{kind: "c2b_validation"}] = Repo.all(Event)
  end

  test "duplicate STK callback still returns 200", %{conn: conn} do
    body = fixture("stk_callback_success.json")

    assert post_json(conn, ~p"/webhooks/daraja/stk", body) |> response(200) == "OK"

    assert build_conn()
           |> post_json(~p"/webhooks/daraja/stk", body)
           |> response(200) == "OK"

    assert [_] = Repo.all(Event)
  end
end
