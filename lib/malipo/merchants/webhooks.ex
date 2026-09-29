defmodule Malipo.Merchants.Webhooks do
  @moduledoc """
  Outbound merchant callbacks — HMAC-SHA256 over the raw JSON body.

  The URL comes from `callback_url` on the payment. An account webhook URL,
  if one was saved earlier, is only used when the payment omits `callback_url`.

  Header: `X-Malipo-Signature: sha256=<hex>`
  Events: `payment.settled` | `payment.failed` (mapped from intent outbox events).
  """

  require Logger

  alias Malipo.Merchants
  alias Malipo.Merchants.ApiKey

  @doc "Map internal outbox event name to public merchant event."
  @spec public_event(String.t()) :: String.t() | nil
  def public_event("intent.settled"), do: "payment.settled"
  def public_event("intent.failed"), do: "payment.failed"
  def public_event("intent.expired"), do: "payment.failed"
  def public_event(_), do: nil

  @doc "HMAC-SHA256 hex digest of `body` with `secret`."
  @spec sign(binary(), String.t()) :: String.t()
  def sign(body, secret) when is_binary(body) and is_binary(secret) do
    :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)
  end

  @doc """
  POST the payment result to the merchant.

  Target, in order: `context.callback_url` on this payment, then the account
  webhook URL if one was saved earlier. No URL means nothing to send.

  Returns `:ok` when skipped or delivered; `{:error, reason}` on HTTP failure.
  """
  @spec deliver(String.t(), map()) :: :ok | {:error, String.t()}
  def deliver(business_id, outbox_payload)
      when is_binary(business_id) and is_map(outbox_payload) do
    event = public_event(outbox_payload["event"] || "")

    with event when is_binary(event) <- event,
         %ApiKey{webhook_secret: secret} = key
         when is_binary(secret) and secret != "" <- Merchants.get_active_key(business_id),
         url when is_binary(url) and url != "" <- notify_url(key, outbox_payload) do
      body =
        Jason.encode!(%{
          "id" => outbox_payload["event_id"],
          "event" => event,
          "created_at" => outbox_payload["occurred_at"],
          "data" => merchant_data(outbox_payload, event)
        })

      sig = sign(body, secret)
      http_post(url, body, sig, key.client_id)
    else
      nil ->
        :ok

      %ApiKey{} ->
        Logger.debug("merchant callback skipped — no url/secret for #{business_id}")
        :ok

      _ ->
        :ok
    end
  end

  # Per-payment callback wins. Account webhook is only the fallback.
  defp notify_url(%ApiKey{webhook_url: account_url}, payload) do
    case get_in(payload, ["context", "callback_url"]) do
      url when is_binary(url) and url != "" -> url
      _ -> account_url
    end
  end

  defp merchant_data(payload, event) do
    base = %{
      "id" => payload["intent_id"],
      "business_id" => payload["business_id"],
      "amount" => payload["amount"],
      "currency" => payload["currency"],
      "reference" => get_in(payload, ["context", "reference"]),
      "status" => if(event == "payment.settled", do: "settled", else: "failed")
    }

    cond do
      event == "payment.settled" ->
        Map.put(base, "receipt", payload["receipt"])

      true ->
        Map.merge(base, %{
          "failure_kind" => payload["failure_kind"],
          "failure_message" => payload["failure_message"]
        })
    end
  end

  defp http_post(url, body, signature, client_id) do
    headers = [
      {"content-type", "application/json"},
      {"accept", "application/json"},
      {"x-malipo-signature", "sha256=" <> signature},
      {"x-malipo-client-id", client_id || ""}
    ]

    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, Malipo.Finch, receive_timeout: 10_000) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: resp}} ->
        {:error, "merchant webhook HTTP #{status}: #{String.slice(to_string(resp), 0, 200)}"}

      {:error, reason} ->
        {:error, Exception.message(reason)}
    end
  end
end
