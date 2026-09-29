defmodule Malipo.Rails.Daraja.PasswordTest do
  use ExUnit.Case, async: true

  alias Malipo.Rails.Daraja.Password

  test "builds Base64(shortcode <> passkey <> timestamp)" do
    assert Password.build("4094529", "passkey", "20260101120000") ==
             Base.encode64("4094529passkey20260101120000")
  end

  test "trims whitespace on shortcode and passkey" do
    assert Password.build(" 4094529 ", " pass\nkey ", "20260101120000") ==
             Password.build("4094529", "passkey", "20260101120000")
  end

  test "timestamp is YYYYMMDDHHMMSS in EAT (UTC+3)" do
    dt = ~U[2026-01-01 09:00:00Z]
    assert Password.timestamp(dt) == "20260101120000"
  end
end
