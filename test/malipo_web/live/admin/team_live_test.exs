defmodule MalipoWeb.Admin.TeamLiveTest do
  use MalipoWeb.ConnCase, async: true

  alias Malipo.AdminUsers

  test "an operator can be added from the console", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_admin() |> live(~p"/admin/team")

    html =
      view
      |> form("#admin-user-form",
        admin_user: %{
          email: "new@example.com",
          name: "New Ops",
          password: "supersecret",
          role: "admin"
        }
      )
      |> render_submit()

    assert html =~ "new@example.com"
    assert AdminUsers.get_by_email("new@example.com")
  end

  test "you cannot deactivate your own account", %{conn: conn} do
    {:ok, user} =
      AdminUsers.create(%{"email" => "self@example.com", "password" => "supersecret"})

    {:ok, view, _html} =
      conn |> log_in_admin("self@example.com") |> live(~p"/admin/team")

    html =
      view
      |> element(~s{#admin-user-#{user.id} button[phx-click="toggle"]})
      |> render_click()

    assert html =~ "cannot deactivate your own account"
    assert AdminUsers.get(user.id).active
  end

  test "the last active operator cannot be deactivated", %{conn: conn} do
    {:ok, one} =
      AdminUsers.create(%{"email" => "one@example.com", "password" => "supersecret"})

    {:ok, two} =
      AdminUsers.create(%{"email" => "two@example.com", "password" => "supersecret"})

    {:ok, _} = AdminUsers.set_active(two, false)

    {:ok, view, _html} = conn |> log_in_admin() |> live(~p"/admin/team")

    html =
      view
      |> element(~s{#admin-user-#{one.id} button[phx-click="toggle"]})
      |> render_click()

    assert html =~ "At least one operator must stay active"
    assert AdminUsers.get(one.id).active
  end

  test "a password can be reset", %{conn: conn} do
    {:ok, user} =
      AdminUsers.create(%{"email" => "reset@example.com", "password" => "supersecret"})

    {:ok, view, _html} = conn |> log_in_admin() |> live(~p"/admin/team")

    html =
      view
      |> element(~s{#admin-user-#{user.id} button[phx-click="reset"]})
      |> render_click()

    assert html =~ "Reset password"

    view
    |> form("#reset-password-form", password: %{password: "brandnewpass"})
    |> render_submit()

    assert {:ok, _} = AdminUsers.authenticate("reset@example.com", "brandnewpass")

    assert {:error, :invalid_credentials} =
             AdminUsers.authenticate("reset@example.com", "supersecret")
  end
end
