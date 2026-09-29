defmodule Malipo.Rails.ClassifyTest do
  use ExUnit.Case, async: true

  alias Malipo.Rails.Classify

  test "4999 + wrong credentials → bad_passkey" do
    failure = Classify.daraja("4999", "Wrong credentials")
    assert failure.kind == :bad_passkey
    assert failure.retryable? == false
  end

  test "4999 without credential wording → pending" do
    failure = Classify.daraja(4999, "The service request is processed successfully.")
    assert failure.kind == :pending
    assert failure.retryable? == true
  end

  test "1032 → subscriber_cancelled" do
    failure = Classify.daraja("1032", "Request cancelled by user")
    assert failure.kind == :subscriber_cancelled
    assert failure.retryable? == false
  end

  test "1037 → timeout (retryable)" do
    failure = Classify.daraja("1037", "DS timeout")
    assert failure.kind == :timeout
    assert failure.retryable? == true
  end

  test "1 → insufficient_funds" do
    failure = Classify.daraja("1", "Insufficient balance")
    assert failure.kind == :insufficient_funds
  end

  test "2001 → wrong_pin" do
    failure = Classify.daraja("2001", "Wrong PIN")
    assert failure.kind == :wrong_pin
  end

  test "query_bucket" do
    assert Classify.query_bucket("0") == :success
    assert Classify.query_bucket("1032") == :failed
    assert Classify.query_bucket("4999", "still processing") == :pending
    assert Classify.query_bucket("4999", "Wrong credentials") == :failed
  end
end
