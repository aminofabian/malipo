defmodule MalipoWeb.Admin.AuthGateTest do
  use MalipoWeb.ConnCase, async: true

  test "unauthenticated visitors are redirected to the login page", %{conn: conn} do
    assert {:error, {_kind, %{to: "/admin/login"}}} = live(conn, ~p"/admin")
    assert {:error, {_kind, %{to: "/admin/login"}}} = live(conn, ~p"/admin/transactions")
    assert {:error, {_kind, %{to: "/admin/login"}}} = live(conn, ~p"/admin/accounts")
  end

  test "the login page renders the form", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/login")

    assert html =~ "super admin console"
    assert html =~ "admin-login-form"
    assert html =~ "Sign in"
  end

  test "signed-in operators reach the console and see who they are", %{conn: conn} do
    conn = log_in_admin(conn)

    {:ok, _view, html} = live(conn, ~p"/admin")

    assert html =~ "Overview"
    assert html =~ "Signed in as"
    assert html =~ "admin"
  end

  test "signed-in operators are bounced away from the login page", %{conn: conn} do
    conn = log_in_admin(conn)

    assert {:error, {_kind, %{to: "/admin"}}} = live(conn, ~p"/admin/login")
  end
end
