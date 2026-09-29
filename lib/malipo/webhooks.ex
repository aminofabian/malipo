defmodule Malipo.Webhooks do
  @moduledoc """
  Daraja webhook ingest — persist raw, 200 OK, process async.

  Controller calls `ingest/3`. Oban `Processor` calls `process/1`.
  STK callbacks settle/fail the matching intent and write an outbox row
  in the same transaction.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Malipo.Fees.Sweep
  alias Malipo.Intents
  alias Malipo.Intents.Intent
  alias Malipo.Rails.Failure
  alias Malipo.Repo
  alias Malipo.Webhooks.{C2bCallback, Event, Processor, StkCallback}

  @doc """
  Persist a raw webhook and enqueue async processing.

  Always safe to call from the controller — duplicates become no-ops via
  `dedupe_key` unique index.
  """
  @spec ingest(String.t(), binary(), map()) ::
          {:ok, Event.t()} | {:ok, :duplicate} | {:error, Ecto.Changeset.t()}
  def ingest(kind, raw_body, headers \\ %{})
      when is_binary(kind) and is_binary(raw_body) do
    payload =
      case Jason.decode(raw_body) do
        {:ok, map} when is_map(map) -> map
        _ -> %{}
      end

    dedupe =
      case kind do
        "stk" ->
          StkCallback.dedupe_key(payload) || StkCallback.dedupe_key(raw_body)

        kind when kind in ["c2b_validation", "c2b_confirmation"] ->
          C2bCallback.dedupe_key(payload) || c2b_dedupe(payload)

        _ ->
          c2b_dedupe(payload)
      end

    attrs = %{
      kind: kind,
      rail: "daraja",
      dedupe_key: dedupe,
      raw_body: raw_body,
      headers: stringify_headers(headers),
      payload: payload
    }

    Multi.new()
    |> Multi.insert(:event, Event.ingest_changeset(attrs))
    |> Oban.insert(:job, fn %{event: event} ->
      Processor.new(%{"webhook_event_id" => event.id})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{event: event}} ->
        {:ok, event}

      {:error, :event, %Ecto.Changeset{} = cs, _} ->
        if dedupe_conflict?(cs) do
          {:ok, :duplicate}
        else
          {:error, cs}
        end

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  @doc "Interpret one webhook_events row."
  @spec process(Ecto.UUID.t()) ::
          {:ok, Event.t()}
          | {:error, :not_found | :duplicate | :ignored | term()}
  def process(id) when is_binary(id) do
    case Repo.get(Event, id) do
      nil ->
        {:error, :not_found}

      %Event{status: status} = event when status in ["processed", "ignored"] ->
        {:ok, event}

      %Event{kind: "stk"} = event ->
        process_stk(event)

      %Event{kind: "c2b_confirmation"} = event ->
        process_c2b_confirmation(event)

      %Event{kind: "c2b_validation"} = event ->
        event
        |> Event.mark_ignored_changeset("validation ack only")
        |> Repo.update()

      %Event{kind: kind} = event when kind in ["b2b_result", "b2b_timeout"] ->
        process_b2b(event, kind)

      %Event{} = event ->
        event
        |> Event.mark_ignored_changeset("unknown kind")
        |> Repo.update()
    end
  end

  defp process_b2b(%Event{} = event, kind) do
    case Malipo.Fees.finalize_sweep_webhook(kind, event.payload) do
      {:ok, %Sweep{} = sweep} ->
        event
        |> Event.mark_processed_changeset(%{intent_id: sweep.intent_id})
        |> Repo.update()

      {:ok, nil} ->
        event
        |> Event.mark_ignored_changeset("no fee sweep for #{kind}")
        |> Repo.update()
    end
  end

  defp process_c2b_confirmation(%Event{} = event) do
    case Malipo.Till.ingest_confirmation(event.payload) do
      {:ok, _receipt, _outcome} ->
        event
        |> Event.mark_processed_changeset(%{})
        |> Repo.update()

      {:error, :invalid_payload} ->
        event
        |> Event.mark_failed_changeset("invalid C2B confirmation payload")
        |> Repo.update()

      {:error, reason} ->
        event
        |> Event.mark_failed_changeset("c2b ingest failed: #{inspect(reason)}")
        |> Repo.update()
        |> case do
          {:ok, _} -> {:error, reason}
          other -> other
        end
    end
  end

  defp process_stk(%Event{} = event) do
    case StkCallback.parse(event.payload) do
      {:error, :invalid_payload} ->
        event
        |> Event.mark_failed_changeset("invalid STK callback payload")
        |> Repo.update()

      {:pending, %{checkout_request_id: checkout}} ->
        event
        |> Event.mark_ignored_changeset("pending at provider (#{checkout})")
        |> Repo.update()

      {:success, result} ->
        settle_from_callback(event, result)

      {:failed, result} ->
        fail_from_callback(event, result)
    end
  end

  defp settle_from_callback(%Event{} = event, result) do
    case find_intent(result.checkout_request_id) do
      nil ->
        event
        |> Event.mark_ignored_changeset(
          "no intent for CheckoutRequestID #{result.checkout_request_id}"
        )
        |> Repo.update()

      %Intent{status: "settled"} = intent ->
        event
        |> Event.mark_processed_changeset(%{intent_id: intent.id})
        |> Repo.update()

      %Intent{} = intent ->
        case Intents.mark_settled(intent, %{
               receipt: result.receipt,
               checkout_request_id: result.checkout_request_id,
               merchant_request_id: result[:merchant_request_id]
             }) do
          {:ok, settled} ->
            event
            |> Event.mark_processed_changeset(%{intent_id: settled.id})
            |> Repo.update()

          {:error, reason} ->
            event
            |> Event.mark_failed_changeset("settle failed: #{inspect(reason)}")
            |> Repo.update()
            |> case do
              {:ok, _} -> {:error, reason}
              other -> other
            end
        end
    end
  end

  defp fail_from_callback(%Event{} = event, result) do
    %Failure{} = failure = result.failure

    case find_intent(result.checkout_request_id) do
      nil ->
        event
        |> Event.mark_ignored_changeset(
          "no intent for CheckoutRequestID #{result.checkout_request_id}"
        )
        |> Repo.update()

      %Intent{status: status} = intent when status in ["settled", "failed", "expired"] ->
        event
        |> Event.mark_processed_changeset(%{intent_id: intent.id})
        |> Repo.update()

      %Intent{} = intent ->
        case Intents.mark_failed(intent, %{
               failure_kind: Atom.to_string(failure.kind),
               failure_message: failure.message,
               failure_provider_code: failure.provider_code && to_string(failure.provider_code)
             }) do
          {:ok, failed} ->
            event
            |> Event.mark_processed_changeset(%{intent_id: failed.id})
            |> Repo.update()

          {:error, reason} ->
            event
            |> Event.mark_failed_changeset("fail failed: #{inspect(reason)}")
            |> Repo.update()
            |> case do
              {:ok, _} -> {:error, reason}
              other -> other
            end
        end
    end
  end

  defp find_intent(checkout_id) when is_binary(checkout_id) do
    Repo.one(
      from(i in Intent,
        where: i.checkout_request_id == ^checkout_id,
        order_by: [desc: i.inserted_at],
        limit: 1
      )
    )
  end

  defp find_intent(_), do: nil

  defp c2b_dedupe(payload) when is_map(payload) do
    payload["TransID"] || payload["TransactionID"] || payload["transID"]
  end

  defp c2b_dedupe(_), do: nil

  defp dedupe_conflict?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {_field, {_, opts}} ->
        opts[:constraint] == :unique or opts[:constraint_name] == :webhook_events_dedupe

      _ ->
        false
    end)
  end

  defp stringify_headers(headers) when is_map(headers) do
    Map.new(headers, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp stringify_headers(headers) when is_list(headers) do
    Map.new(headers, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp stringify_headers(_), do: %{}
end
