defmodule Malipo.Admin do
  @moduledoc """
  Read-only aggregates that power the super-admin console.

  Everything here is a projection over data Malipo already owns — Connect
  accounts, merchant destinations/keys, STK intents, C2B till receipts, and the
  settlement outbox. No writes, no money movement.
  """

  import Ecto.Query

  alias Malipo.ConnectAccounts.Account
  alias Malipo.Intents.{Attempt, Intent}
  alias Malipo.Merchants.{ApiKey, Destination}
  alias Malipo.Outbox.Event
  alias Malipo.Repo
  alias Malipo.Till.Receipt

  @dashboards_currency "KES"

  @doc "Headline counts and volumes for the dashboard."
  @spec overview() :: map()
  def overview do
    now = DateTime.utc_now()
    day_ago = DateTime.add(now, -24, :hour)
    week_ago = DateTime.add(now, -7, :day)

    settled = from(i in Intent, where: i.status == "settled")
    matched_receipts = from(r in Receipt, where: r.status == "matched")

    %{
      generated_at: now,
      currency: @dashboards_currency,
      accounts: %{
        total: Repo.aggregate(Account, :count, :id),
        new_7d: Repo.aggregate(from(a in Account, where: a.inserted_at >= ^week_ago), :count, :id)
      },
      merchants: %{
        destinations: Repo.aggregate(Destination, :count, :id),
        collecting:
          Repo.aggregate(
            from(d in Destination, where: d.active == true and d.verified == true),
            :count,
            :id
          ),
        keys: Repo.aggregate(from(k in ApiKey, where: is_nil(k.revoked_at)), :count, :id)
      },
      intents: %{
        total: Repo.aggregate(Intent, :count, :id),
        settled: Repo.aggregate(settled, :count, :id),
        failed: Repo.aggregate(from(i in Intent, where: i.status == "failed"), :count, :id),
        open:
          Repo.aggregate(
            from(i in Intent, where: i.status in ["pending", "prompted"]),
            :count,
            :id
          ),
        last_24h:
          Repo.aggregate(from(i in Intent, where: i.inserted_at >= ^day_ago), :count, :id),
        settled_volume: sum_amount(settled),
        settled_volume_24h: sum_amount(from(i in settled, where: i.settled_at >= ^day_ago)),
        settled_volume_7d: sum_amount(from(i in settled, where: i.settled_at >= ^week_ago))
      },
      till: %{
        total: Repo.aggregate(Receipt, :count, :id),
        matched: Repo.aggregate(matched_receipts, :count, :id),
        unmatched:
          Repo.aggregate(from(r in Receipt, where: r.status == "unmatched"), :count, :id),
        matched_volume: sum_amount(matched_receipts)
      },
      outbox: %{
        pending: Repo.aggregate(from(o in Event, where: o.status == "pending"), :count, :id),
        failed: Repo.aggregate(from(o in Event, where: o.status == "failed"), :count, :id),
        delivered: Repo.aggregate(from(o in Event, where: o.status == "delivered"), :count, :id)
      }
    }
  end

  @doc """
  Connect accounts newest-first, each enriched with its active destination,
  API key, and intent rollup (count + settled volume).
  """
  @spec list_accounts(non_neg_integer()) :: [map()]
  def list_accounts(limit \\ 100) when is_integer(limit) do
    accounts =
      Repo.all(from(a in Account, order_by: [desc: a.inserted_at], limit: ^limit))

    business_ids = Enum.map(accounts, & &1.business_id)

    destinations = destinations_by_business(business_ids)
    keys = keys_by_business(business_ids)
    {intent_counts, settled} = intent_rollups(business_ids)

    Enum.map(accounts, fn account ->
      {settled_count, settled_volume} = Map.get(settled, account.business_id, {0, zero()})

      %{
        account: account,
        destination: Map.get(destinations, account.business_id),
        key: Map.get(keys, account.business_id),
        intent_count: Map.get(intent_counts, account.business_id, 0),
        settled_count: settled_count,
        settled_volume: settled_volume
      }
    end)
  end

  @doc """
  A single chronological feed of money movement: STK intents and C2B till
  receipts, newest first.

  `kind` is `"all"`, `"stk"`, or `"c2b"`.
  """
  @spec list_transactions(non_neg_integer(), String.t()) :: [map()]
  def list_transactions(limit \\ 100, kind \\ "all") when is_integer(limit) do
    intents =
      if kind in ["all", "stk"] do
        Repo.all(from(i in Intent, order_by: [desc: i.inserted_at], limit: ^limit))
        |> Enum.map(&transaction_from_intent/1)
      else
        []
      end

    receipts =
      if kind in ["all", "c2b"] do
        Repo.all(from(r in Receipt, order_by: [desc: r.inserted_at], limit: ^limit))
        |> Enum.map(&transaction_from_receipt/1)
      else
        []
      end

    (intents ++ receipts)
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
    |> Enum.take(limit)
  end

  @doc """
  Full read-only view of one intent: its rail attempts, related outbox events,
  and the C2B receipt that settled it (if any).

  Returns `{:ok, map}` or `{:error, :not_found}`.
  """
  @spec intent_detail(String.t()) :: {:ok, map()} | {:error, :not_found}
  def intent_detail(id) when is_binary(id) do
    case Repo.get(Intent, id) do
      nil ->
        {:error, :not_found}

      %Intent{} = intent ->
        attempts =
          from(a in Attempt,
            where: a.intent_id == ^intent.id,
            order_by: [asc: a.attempt_number]
          )
          |> Repo.all()

        events =
          from(e in Event,
            where: e.intent_id == ^intent.id,
            order_by: [desc: e.inserted_at]
          )
          |> Repo.all()

        receipt =
          from(r in Receipt,
            where: r.matched_intent_id == ^intent.id,
            order_by: [desc: r.inserted_at],
            limit: 1
          )
          |> Repo.one()

        {:ok, %{intent: intent, attempts: attempts, events: events, receipt: receipt}}
    end
  end

  @doc false
  def transaction_from_intent(%Intent{} = intent) do
    %{
      id: "intent-" <> intent.id,
      kind: "stk",
      at: intent.inserted_at,
      status: intent.status,
      amount: intent.amount,
      currency: intent.currency,
      reference: intent.receipt || intent.checkout_request_id || intent.idempotency_key,
      payer_msisdn: intent.payer_msisdn,
      payer_name: nil,
      business_id: intent.business_id,
      failure_kind: intent.failure_kind,
      intent_id: intent.id
    }
  end

  @doc false
  def transaction_from_receipt(%Receipt{} = receipt) do
    %{
      id: "receipt-" <> receipt.id,
      kind: "c2b",
      at: receipt.inserted_at,
      status: receipt.status,
      amount: receipt.amount,
      currency: receipt.currency,
      reference: receipt.trans_id,
      payer_msisdn: receipt.payer_msisdn,
      payer_name: receipt.payer_name,
      business_id: receipt.business_id,
      failure_kind: nil,
      intent_id: receipt.matched_intent_id
    }
  end

  defp destinations_by_business([]), do: %{}

  defp destinations_by_business(business_ids) do
    from(d in Destination,
      where: d.business_id in ^business_ids,
      # active rows first, then newest, so put_new/3 keeps the collection row.
      order_by: [desc: d.active, desc: d.inserted_at]
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn destination, acc ->
      Map.put_new(acc, destination.business_id, destination)
    end)
  end

  defp keys_by_business([]), do: %{}

  defp keys_by_business(business_ids) do
    from(k in ApiKey,
      where: k.business_id in ^business_ids and is_nil(k.revoked_at),
      order_by: [desc: k.inserted_at]
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn key, acc -> Map.put_new(acc, key.business_id, key) end)
  end

  defp intent_rollups([]), do: {%{}, %{}}

  defp intent_rollups(business_ids) do
    counts =
      from(i in Intent,
        where: i.business_id in ^business_ids,
        group_by: i.business_id,
        select: {i.business_id, count(i.id)}
      )
      |> Repo.all()
      |> Map.new()

    settled =
      from(i in Intent,
        where: i.business_id in ^business_ids and i.status == "settled",
        group_by: i.business_id,
        select: {i.business_id, count(i.id), sum(i.amount)}
      )
      |> Repo.all()
      |> Map.new(fn {business_id, count, volume} ->
        {business_id, {count, zero_if_nil(volume)}}
      end)

    {counts, settled}
  end

  defp sum_amount(queryable) do
    queryable
    |> select([q], sum(q.amount))
    |> Repo.one()
    |> zero_if_nil()
  end

  defp zero_if_nil(nil), do: zero()
  defp zero_if_nil(%Decimal{} = value), do: value
  defp zero, do: Decimal.new(0)
end
