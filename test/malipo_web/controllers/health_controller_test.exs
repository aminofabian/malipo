defmodule MalipoWeb.HealthControllerTest do
  use MalipoWeb.ConnCase, async: false

  test "GET /health is live", %{conn: conn} do
    assert json_response(get(conn, ~p"/health"), 200)["status"] == "ok"
  end

  test "GET /ready reports database and vault", %{conn: conn} do
    body = json_response(get(conn, ~p"/ready"), 200)
    assert body["status"] == "ready"
    assert body["checks"]["database"]["status"] == "ok"
    assert body["checks"]["vault"]["status"] == "ok"
  end
end
