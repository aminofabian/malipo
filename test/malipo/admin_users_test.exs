defmodule Malipo.AdminUsersTest do
  use Malipo.DataCase, async: true

  alias Malipo.AdminUsers

  test "create normalizes the email and never returns the raw password" do
    assert {:ok, user} =
             AdminUsers.create(%{
               "email" => "Ops@Example.com",
               "password" => "supersecret",
               "name" => "Ops"
             })

    assert user.email == "ops@example.com"
    assert user.name == "Ops"
    assert user.active
    assert user.role == "admin"
    refute user.password_hash =~ "supersecret"
  end

  test "duplicate email is rejected" do
    {:ok, _} = AdminUsers.create(%{"email" => "dup@example.com", "password" => "supersecret"})

    assert {:error, cs} =
             AdminUsers.create(%{"email" => "dup@example.com", "password" => "supersecret"})

    assert %{email: ["has already been taken"]} = errors_on(cs)
  end

  test "short password is rejected" do
    assert {:error, cs} =
             AdminUsers.create(%{"email" => "short@example.com", "password" => "short"})

    assert %{password: _} = errors_on(cs)
  end

  test "authenticate stamps last login and enforces the active flag" do
    {:ok, user} =
      AdminUsers.create(%{"email" => "login@example.com", "password" => "supersecret"})

    assert {:ok, logged_in} = AdminUsers.authenticate("login@example.com", "supersecret")
    refute is_nil(logged_in.last_login_at)

    assert {:error, :invalid_credentials} =
             AdminUsers.authenticate("login@example.com", "wrong")

    {:ok, _} = AdminUsers.set_active(user, false)

    assert {:error, :invalid_credentials} =
             AdminUsers.authenticate("login@example.com", "supersecret")
  end

  test "update_password rotates credentials" do
    {:ok, user} =
      AdminUsers.create(%{"email" => "rotate@example.com", "password" => "supersecret"})

    assert {:ok, _} = AdminUsers.update_password(user, %{"password" => "brandnewpass"})

    assert {:error, :invalid_credentials} =
             AdminUsers.authenticate("rotate@example.com", "supersecret")

    assert {:ok, _} = AdminUsers.authenticate("rotate@example.com", "brandnewpass")
  end

  test "any_active? tracks whether any operator can sign in" do
    refute AdminUsers.any_active?()

    {:ok, user} =
      AdminUsers.create(%{"email" => "active@example.com", "password" => "supersecret"})

    assert AdminUsers.any_active?()

    {:ok, _} = AdminUsers.set_active(user, false)
    refute AdminUsers.any_active?()
  end
end
