defmodule Malipo.Outbox.Dispatcher do
  @moduledoc """
  POSTs an outbox row to:
  1. the monolith payment-events inbox (`MONOLITH_PAYMENT_EVENTS_URL`), and
  2. the merchant callback — `callback_url` on the payment, or the account
     webhook URL when the payment did not include one (HMAC-signed).

  Either target may be skipped. Delivery succeeds only when every *attempted*
  target succeeds. Retries for 24h via Oban + outbox backoff.
  """

  use Oban.Worker, queue: :outbox, max_attempts: 40

  require Logger

  alias Malipo.Merchants.Webhooks, as: MerchantWebhooks
  alias Malipo.Outbox
  alias Malipo.Outbox.Event

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"outbox_id" => id}}) do
    case Outbox.get(id) do
      nil ->
        :ok

      %Event{status: "delivered"} ->
        :ok

      %Event{status: "failed"} ->
        :ok

      %Event{} = row ->
        dispatch(row)
    end
  end

  defp dispatch(%Event{} = row) do
    payload = row.payload |> Map.put("event_id", row.event_id)

    results = [
      post_monolith(payload),
      MerchantWebhooks.deliver(row.business_id, payload)
    ]

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        {:ok, _} = Outbox.mark_delivered(row)
        :ok

      {:error, reason} ->
        msg = format_error(reason)
        {:ok, updated} = Outbox.mark_attempt(row, msg)

        if updated.status == "failed" do
          Logger.error("outbox #{row.event_id} exhausted retries: #{msg}")
          :ok
        else
          {:error, msg}
        end
    end
  end

  defp post_monolith(payload) do
    case Application.get_env(:malipo, :monolith_payment_events_url) ||
           System.get_env("MONOLITH_PAYMENT_EVENTS_URL") do
      url when is_binary(url) and url != "" ->
        http_post(url, payload)

      _ ->
        Logger.debug("outbox monolith deliver skipped — MONOLITH_PAYMENT_EVENTS_URL unset")
        :ok
    end
  end

  defp http_post(url, payload) do
    headers = [
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ]

    body = Jason.encode!(payload)
    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, Malipo.Finch, receive_timeout: 10_000) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: resp}} ->
        {:error, "HTTP #{status}: #{String.slice(to_string(resp), 0, 200)}"}

      {:error, reason} ->
        {:error, Exception.message(reason)}
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
