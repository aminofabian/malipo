defmodule MalipoWeb.ConnectAuthControllerTest do
  use MalipoWeb.ConnCase, async: false

  alias Malipo.ConnectAccounts

  test "register then login", %{conn: conn} do
    body =
      post(conn, ~p"/internal/v1/connect/register", %{
        "email" => "Shop@Example.com",
        "password" => "secret123",
        "display_name" => "Shop Ltd"
      })
      |> json_response(201)

    assert body["email"] == "shop@example.com"
    assert body["display_name"] == "Shop Ltd"
    assert String.starts_with?(body["business_id"], "biz_")

    assert %{"business_id" => biz, "email" => "shop@example.com"} =
             post(conn, ~p"/internal/v1/connect/login", %{
               "email" => "shop@example.com",
               "password" => "secret123"
             })
             |> json_response(200)

    assert biz == body["business_id"]
  end

  test "duplicate email rejected", %{conn: conn} do
    assert {:ok, _} =
             ConnectAccounts.register(%{
               "email" => "dup@example.com",
               "password" => "secret123"
             })

    assert json_response(
             post(conn, ~p"/internal/v1/connect/register", %{
               "email" => "dup@example.com",
               "password" => "secret123"
             }),
             422
           )["error"] == "invalid"
  end

  test "bad password returns 401", %{conn: conn} do
    assert {:ok, _} =
             ConnectAccounts.register(%{
               "email" => "auth@example.com",
               "password" => "secret123"
             })

    assert json_response(
             post(conn, ~p"/internal/v1/connect/login", %{
               "email" => "auth@example.com",
               "password" => "wrong-password"
             }),
             401
           )["error"] == "invalid_credentials"
  end

  test "short password rejected", %{conn: conn} do
    assert json_response(
             post(conn, ~p"/internal/v1/connect/register", %{
               "email" => "short@example.com",
               "password" => "short"
             }),
             422
           )["error"] == "invalid"
  end
end
