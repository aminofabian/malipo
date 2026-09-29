defmodule Malipo.MsisdnTest do
  use ExUnit.Case, async: true

  alias Malipo.Msisdn

  test "normalises local 07… numbers to 2547…" do
    assert Msisdn.normalise("0712 345 678") == {:ok, "254712345678"}
  end

  test "accepts already-international MSISDNs" do
    assert Msisdn.normalise("254712345678") == {:ok, "254712345678"}
  end

  test "rejects junk" do
    assert Msisdn.normalise("not-a-phone") == {:error, :invalid_phone}
  end
end
