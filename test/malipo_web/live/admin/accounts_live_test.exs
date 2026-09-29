defmodule MalipoWeb.Admin.AccountsLiveTest do
  use MalipoWeb.ConnCase, async: true

  alias Malipo.ConnectAccounts

  test "lists merchants who signed up", %{conn: conn} do
    {:ok, account} =
      ConnectAccounts.register(%{"email" => "listed@example.com", "password" => "secret123"})

    {:ok, _view, html} = conn |> log_in_admin() |> live(~p"/admin/accounts")

    assert html =~ "Accounts"
    assert html =~ "listed@example.com"
    assert html =~ account.business_id
  end

  test "empty state when nobody has signed up", %{conn: conn} do
    {:ok, _view, html} = conn |> log_in_admin() |> live(~p"/admin/accounts")

    assert html =~ "No accounts have signed up yet."
  end
end
