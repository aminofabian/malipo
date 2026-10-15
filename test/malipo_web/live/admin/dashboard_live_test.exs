defmodule MalipoWeb.Admin.DashboardLiveTest do
  use MalipoWeb.ConnCase, async: true

  test "overview groups the console and filters the recent list", %{conn: conn} do
    conn = log_in_admin(conn, "ops@malipo.test")
    {:ok, view, html} = live(conn, ~p"/admin")

    assert html =~ "Overview"
    assert html =~ "Money"
    assert html =~ "Needs attention"
    assert html =~ "Settled volume"
    assert html =~ "ops@malipo.test"
    assert html =~ "Receipts"

    failed = view |> element("button", "Failed") |> render_click()
    assert failed =~ "No failed payments in this list."

    hidden = view |> element("button", "Hide test") |> render_click()
    assert hidden =~ "Show test"

    {:ok, _view, fees} = live(conn, ~p"/admin/fees")
    assert fees =~ "Config"
    assert fees =~ "Fees"
  end
end
