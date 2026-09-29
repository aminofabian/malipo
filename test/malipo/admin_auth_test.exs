defmodule Malipo.AdminAuthTest do
  use Malipo.DataCase, async: true

  alias Malipo.AdminAuth
  alias Malipo.AdminUsers

  test "available? is true when the env break-glass credential is configured" do
    assert AdminAuth.available?()
  end

  test "authenticate accepts the env break-glass credential" do
    assert AdminAuth.authenticate("admin", "admin") == :ok
  end

  test "authenticate rejects wrong credentials and non-strings" do
    assert AdminAuth.authenticate("admin", "nope") == :error
    assert AdminAuth.authenticate("root", "admin") == :error
    assert AdminAuth.authenticate("admin", "") == :error
    assert AdminAuth.authenticate(nil, nil) == :error
    assert AdminAuth.authenticate(123, 456) == :error
  end

  test "authenticate accepts a DB operator, case-insensitively" do
    {:ok, _} = AdminUsers.create(%{"email" => "ops@example.com", "password" => "supersecret"})

    assert AdminAuth.authenticate("ops@example.com", "supersecret") == :ok
    assert AdminAuth.authenticate("OPS@example.com", "supersecret") == :ok
    assert AdminAuth.authenticate("ops@example.com", "wrong") == :error
  end
end
