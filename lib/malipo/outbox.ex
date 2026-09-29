defmodule Malipo.Outbox do
  @moduledoc """
  Transactional outbox for settlement events the monolith consumes.

  Write outbox rows in the same txn as intent settlement; Oban dispatches
  `POST /internal/v1/payment-events` on the Java side.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Malipo.Intents.Intent
  alias Malipo.Outbox.{Dispatcher, Event}
  alias Malipo.Repo

  @doc "Build a changeset for an intent terminal event (caller inserts in Multi)."
  @spec build_for_intent(Intent.t(), String.t()) :: Ecto.Changeset.t()
  def build_for_intent(%Intent{} = intent, event)
      when event in ["intent.settled", "intent.failed", "intent.expired"] do
    event_id = event_id()

    Event.create_changeset(%{
      event_id: event_id,
      event: event,
      business_id: intent.business_id,
      intent_id: intent.id,
      payload: payload_for(intent, event, event_id),
      next_attempt_at: DateTime.utc_now()
    })
  end

  @doc "Build outbox row for an unmatched till receipt."
  @spec build_for_till_receipt(Malipo.Till.Receipt.t(), String.t()) :: Ecto.Changeset.t()
  def build_for_till_receipt(%Malipo.Till.Receipt{} = receipt, "till_receipt.unmatched") do
    event_id = event_id()

    Event.create_changeset(%{
      event_id: event_id,
      event: "till_receipt.unmatched",
      business_id: receipt.business_id || "unknown",
      intent_id: nil,
      payload: %{
        "event_id" => event_id,
        "event" => "till_receipt.unmatched",
        "version" => 1,
        "occurred_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "business_id" => receipt.business_id,
        "receipt_id" => receipt.id,
        "trans_id" => receipt.trans_id,
        "shortcode" => receipt.shortcode,
        "amount" => Decimal.to_string(receipt.amount),
        "currency" => receipt.currency,
        "rail" => receipt.rail,
        "bill_ref" => receipt.bill_ref,
        "payer" => %{
          "msisdn_masked" => mask_msisdn(receipt.payer_msisdn),
          "name" => receipt.payer_name
        },
        "trans_time" => receipt.trans_time
      },
      next_attempt_at: DateTime.utc_now()
    })
  end

  @doc "Enqueue an Oban dispatch job for an outbox row (same Multi preferred)."
  @spec enqueue_dispatch(Multi.t(), Event.t()) :: Multi.t()
  def enqueue_dispatch(%Multi{} = multi, %Event{id: id}) when is_binary(id) do
    Oban.insert(multi, :outbox_dispatch, Dispatcher.new(%{"outbox_id" => id}))
  end

  @doc "Fetch a pending/failed-retry row by id."
  @spec get(Ecto.UUID.t()) :: Event.t() | nil
  def get(id) when is_binary(id), do: Repo.get(Event, id)

  @doc "Mark delivered after a successful POST to the monolith."
  @spec mark_delivered(Event.t()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def mark_delivered(%Event{} = row) do
    row |> Event.mark_delivered_changeset() |> Repo.update()
  end

  @doc "Record a failed dispatch attempt with backoff."
  @spec mark_attempt(Event.t(), String.t()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def mark_attempt(%Event{} = row, error) when is_binary(error) do
    next = DateTime.add(DateTime.utc_now(), backoff_seconds(row.attempts + 1), :second)
    row |> Event.mark_attempt_changeset(error, next) |> Repo.update()
  end

  @doc "Pending rows due for dispatch."
  @spec list_due(non_neg_integer()) :: [Event.t()]
  def list_due(limit \\ 100) do
    now = DateTime.utc_now()

    from(o in Event,
      where: o.status == "pending" and (is_nil(o.next_attempt_at) or o.next_attempt_at <= ^now),
      order_by: [asc: o.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc "Recent outbox rows newest-first (ops console)."
  @spec list_recent(non_neg_integer()) :: [Event.t()]
  def list_recent(limit \\ 50) do
    from(o in Event,
      order_by: [desc: o.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp payload_for(%Intent{} = intent, event, event_id) do
    base = %{
      "event_id" => event_id,
      "event" => event,
      "version" => 1,
      "occurred_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "business_id" => intent.business_id,
      "intent_id" => intent.id,
      "idempotency_key" => intent.idempotency_key,
      "context" => intent.context || %{},
      "amount" => Decimal.to_string(intent.amount),
      "currency" => intent.currency,
      "rail" => intent.rail,
      "payer" => %{"msisdn_masked" => mask_msisdn(intent.payer_msisdn)}
    }

    case event do
      "intent.settled" ->
        Map.merge(base, %{
          "receipt" => intent.receipt,
          "settled_at" => intent.settled_at && DateTime.to_iso8601(intent.settled_at),
          "fee" => decimal_or_nil(intent.fee_amount),
          "net" => decimal_or_nil(intent.net_amount),
          "fee_destination" => Malipo.Fees.destination()
        })

      "intent.failed" ->
        Map.merge(base, %{
          "failure_kind" => intent.failure_kind,
          "failure_message" => intent.failure_message,
          "failed_at" => intent.failed_at && DateTime.to_iso8601(intent.failed_at)
        })

      "intent.expired" ->
        Map.merge(base, %{
          "expired_at" => intent.expired_at && DateTime.to_iso8601(intent.expired_at)
        })
    end
  end

  defp event_id do
    "evt_" <> (Ecto.UUID.generate() |> String.replace("-", ""))
  end

  defp decimal_or_nil(nil), do: nil
  defp decimal_or_nil(%Decimal{} = d), do: Decimal.to_string(d)

  defp mask_msisdn(msisdn) when is_binary(msisdn) and byte_size(msisdn) >= 7 do
    prefix = String.slice(msisdn, 0, 4)
    suffix = String.slice(msisdn, -3, 3)
    prefix <> "****" <> suffix
  end

  defp mask_msisdn(_), do: "****"

  # ~40 attempts over 24h with exponential-ish backoff (cap 1h).
  defp backoff_seconds(n) when n <= 1, do: 5
  defp backoff_seconds(n) when n <= 5, do: 30
  defp backoff_seconds(n) when n <= 10, do: 120
  defp backoff_seconds(n) when n <= 20, do: 600
  defp backoff_seconds(_), do: 3600
end
