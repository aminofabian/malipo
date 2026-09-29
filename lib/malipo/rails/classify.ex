defmodule Malipo.Rails.Classify do
  @moduledoc """
  Maps provider result codes / descriptions onto `Malipo.Rails.Failure`.

  Source of truth: Daraja scope §5.3. Expand as fixtures land under
  `test/malipo/rails/daraja/fixtures/`.
  """

  alias Malipo.Rails.Failure

  @spec daraja(String.t() | integer() | nil, String.t() | nil, term()) :: Failure.t()
  def daraja(code, desc, raw \\ nil) do
    code_s = code |> to_string() |> String.trim()
    desc_s = desc || ""

    cond do
      code_s in ["0", "00"] ->
        Failure.new(:unknown, "Unexpected success code in failure path",
          provider_code: code_s,
          raw: raw
        )

      # 4999 + Wrong credentials → bad passkey (not "still pending")
      code_s == "4999" and wrong_credentials?(desc_s) ->
        Failure.new(:bad_passkey, desc_s,
          provider_code: code_s,
          retryable?: false,
          raw: raw
        )

      code_s == "4999" ->
        Failure.new(:pending, blank_to(desc_s, "Waiting for Safaricom"),
          provider_code: code_s,
          retryable?: true,
          raw: raw
        )

      code_s == "1032" ->
        Failure.new(:subscriber_cancelled, blank_to(desc_s, "Customer cancelled the prompt"),
          provider_code: code_s,
          retryable?: false,
          raw: raw
        )

      code_s == "1037" ->
        Failure.new(:timeout, blank_to(desc_s, "Customer didn't respond — resend"),
          provider_code: code_s,
          retryable?: true,
          raw: raw
        )

      code_s == "1" ->
        Failure.new(:insufficient_funds, blank_to(desc_s, "Customer has insufficient M-Pesa balance"),
          provider_code: code_s,
          retryable?: false,
          raw: raw
        )

      code_s == "2001" ->
        Failure.new(:wrong_pin, blank_to(desc_s, "Wrong M-Pesa PIN"),
          provider_code: code_s,
          retryable?: true,
          raw: raw
        )

      code_s == "1019" ->
        Failure.new(:timeout, blank_to(desc_s, "STK prompt expired"),
          provider_code: code_s,
          retryable?: true,
          raw: raw
        )

      true ->
        Failure.new(:unknown, blank_to(desc_s, "Unclassified Daraja failure"),
          provider_code: code_s,
          retryable?: true,
          raw: raw
        )
    end
  end

  @doc "True when ResultDesc / errorMessage indicates a bad Lipa passkey."
  @spec wrong_credentials?(String.t() | nil) :: boolean()
  def wrong_credentials?(nil), do: false

  def wrong_credentials?(desc) when is_binary(desc) do
    d = String.downcase(desc)
    String.contains?(d, "wrong credentials") or String.contains?(d, "merchantvalidate")
  end

  @doc """
  Bucket a query ResultCode the way the poller needs:

  * `:success` — money moved (`0`)
  * `:failed` — terminal customer/provider outcomes
  * `:pending` — still on the handset / unknown codes (incl. bare `4999`)
  """
  @spec query_bucket(String.t() | integer() | nil, String.t() | nil) ::
          :success | :failed | :pending
  def query_bucket(code, desc \\ nil) do
    code_s = code |> to_string() |> String.trim()

    cond do
      code_s in ["0", "00"] -> :success
      code_s == "4999" and wrong_credentials?(desc) -> :failed
      code_s in ["1", "1019", "1032", "1037", "2001"] -> :failed
      true -> :pending
    end
  end

  defp blank_to("", fallback), do: fallback
  defp blank_to(nil, fallback), do: fallback
  defp blank_to(value, _fallback), do: value
end
