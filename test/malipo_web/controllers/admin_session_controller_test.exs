defmodule MalipoWeb.AdminSessionControllerTest do
  use MalipoWeb.ConnCase, async: true

  test "valid credentials sign in and redirect to the console", %{conn: conn} do
    conn =
      post(conn, ~p"/admin/login", %{
        "admin" => %{"user" => "admin", "password" => "admin"}
      })

    assert redirected_to(conn) == "/admin"
    assert get_session(conn, :admin_user) == "admin"
  end

  test "invalid credentials flash and stay on the login page", %{conn: conn} do
    conn =
      post(conn, ~p"/admin/login", %{
        "admin" => %{"user" => "admin", "password" => "wrong"}
      })

    assert redirected_to(conn) == "/admin/login"
    assert get_session(conn, :admin_user) == nil
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid credentials"
  end

  test "missing params are refused", %{conn: conn} do
    conn = post(conn, ~p"/admin/login", %{})

    assert redirected_to(conn) == "/admin/login"
    assert get_session(conn, :admin_user) == nil
  end

  test "sign out clears the session", %{conn: conn} do
    conn = conn |> log_in_admin() |> delete(~p"/admin/logout")

    assert redirected_to(conn) == "/admin/login"
    assert get_session(conn, :admin_user) == nil
  end
end
