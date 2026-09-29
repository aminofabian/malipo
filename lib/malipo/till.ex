defmodule Malipo.Till do
  @moduledoc """
  Inbound C2B till / paybill receipts.

  Confirmations are stored first. If a pending/prompted intent matches the
  BillRefNumber, the intent is settled; otherwise the receipt stays
  `unmatched` and a `till_receipt.unmatched` outbox event is written.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Malipo.Intents
  alias Malipo.Intents.Intent
  alias Malipo.Outbox
  alias Malipo.Repo
  alias Malipo.Till.Receipt
  alias Malipo.Webhooks.C2bCallback

  @doc "Fetch by TransID."
  @spec get_by_trans_id(String.t()) :: Receipt.t() | nil
  def get_by_trans_id(trans_id) when is_binary(trans_id) do
    Repo.get_by(Receipt, rail: "daraja", trans_id: trans_id)
  end

  @doc "Unmatched receipts newest-first."
  @spec list_unmatched(non_neg_integer()) :: [Receipt.t()]
  def list_unmatched(limit \\ 100) do
    from(r in Receipt,
      where: r.status == "unmatched",
      order_by: [desc: r.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc "Recent till receipts newest-first."
  @spec list_recent(non_neg_integer()) :: [Receipt.t()]
  def list_recent(limit \\ 50) do
    from(r in Receipt,
      order_by: [desc: r.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Persist a C2B confirmation and attempt intent match.

  Returns `{:ok, receipt, :matched | :unmatched | :duplicate}`.
  """
  @spec ingest_confirmation(map() | String.t()) ::
          {:ok, Receipt.t(), :matched | :unmatched | :duplicate}
          | {:error, :invalid_payload | Ecto.Changeset.t() | term()}
  def ingest_confirmation(raw) do
    with {:ok, parsed} <- C2bCallback.parse(raw) do
      case get_by_trans_id(parsed.trans_id) do
        %Receipt{} = existing ->
          {:ok, existing, :duplicate}

        nil ->
          insert_and_resolve(parsed)
      end
    end
  end

  defp insert_and_resolve(parsed) do
    attrs = %{
      trans_id: parsed.trans_id,
      shortcode: parsed.shortcode,
      amount: parsed.amount,
      payer_msisdn: parsed.payer_msisdn,
      payer_name: parsed.payer_name,
      bill_ref: parsed.bill_ref,
      transaction_type: parsed.transaction_type,
      trans_time: parsed.trans_time,
      raw_payload: parsed.raw
    }

    case find_match(parsed) do
      %Intent{} = intent ->
        settle_matched(attrs, intent, parsed)

      nil ->
        record_unmatched(attrs, parsed)
    end
  end

  defp settle_matched(attrs, %Intent{} = intent, parsed) do
    Multi.new()
    |> Multi.insert(:receipt, Receipt.create_changeset(attrs))
    |> Multi.run(:settle, fn _repo, _ ->
      case intent.status do
        "settled" ->
          {:ok, intent}

        status when status in ["prompted", "failed", "expired"] ->
          Intents.mark_settled(intent, %{receipt: parsed.trans_id})

        other ->
          {:error, {:invalid_status, other}}
      end
    end)
    |> Multi.update(:mark, fn %{receipt: receipt, settle: settled} ->
      Receipt.mark_matched_changeset(receipt, settled.id, settled.business_id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{mark: receipt}} ->
        {:ok, receipt, :matched}

      {:error, :receipt, %Ecto.Changeset{} = cs, _} ->
        if unique_trans?(cs) do
          {:ok, get_by_trans_id(parsed.trans_id), :duplicate}
        else
          {:error, cs}
        end

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  defp record_unmatched(attrs, parsed) do
    business_id = attrs[:business_id] || inferred_business_id(parsed) || "unknown"

    Multi.new()
    |> Multi.insert(
      :receipt,
      Receipt.create_changeset(Map.put(attrs, :business_id, business_id))
    )
    |> Multi.insert(:outbox, fn %{receipt: receipt} ->
      Outbox.build_for_till_receipt(receipt, "till_receipt.unmatched")
    end)
    |> Multi.merge(fn %{outbox: row} ->
      Outbox.enqueue_dispatch(Multi.new(), row)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{receipt: receipt}} ->
        {:ok, receipt, :unmatched}

      {:error, :receipt, %Ecto.Changeset{} = cs, _} ->
        if unique_trans?(cs) do
          {:ok, get_by_trans_id(parsed.trans_id), :duplicate}
        else
          {:error, cs}
        end

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  defp find_match(%{bill_ref: bill_ref} = parsed) when is_binary(bill_ref) and bill_ref != "" do
    from(i in Intent,
      where:
        i.status in ^["prompted", "failed", "expired"] and
          (i.idempotency_key == ^bill_ref or
             i.checkout_request_id == ^bill_ref or
             fragment("?->>'id' = ?", i.context, ^bill_ref)),
      order_by: [desc: i.inserted_at],
      limit: 1
    )
    |> Repo.one()
    |> case do
      %Intent{} = intent -> intent
      nil -> find_match_by_amount_phone(parsed)
    end
  end

  defp find_match(parsed), do: find_match_by_amount_phone(parsed)

  defp find_match_by_amount_phone(%{amount: amount, payer_msisdn: phone})
       when not is_nil(amount) and is_binary(phone) and phone != "" do
    since = DateTime.add(DateTime.utc_now(), -30 * 60, :second)

    from(i in Intent,
      where:
        i.status == "prompted" and
          i.payer_msisdn == ^phone and
          i.amount == ^amount and
          i.inserted_at >= ^since,
      order_by: [desc: i.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  defp find_match_by_amount_phone(_), do: nil

  defp inferred_business_id(%{bill_ref: ref}) when is_binary(ref) do
    # Bill refs sometimes embed business ids; leave nil/unknown for ops to assign.
    nil
  end

  defp inferred_business_id(_), do: nil

  @doc """
  Race fix: Buy Goods money arrived before the till-await row existed.

  Finds one clear unmatched receipt for this business + amount (+ phone when
  set) and settles the await. Skips when amount matches are ambiguous.
  """
  @spec late_bind_await(Intent.t()) ::
          {:ok, Intent.t()} | :none | {:error, term()}
  def late_bind_await(%Intent{status: status} = intent)
      when status in ["prompted", "failed", "expired"] do
    case find_clear_pending_match(intent.business_id, intent.amount, intent.payer_msisdn) do
      %Receipt{trans_id: receipt_id} = receipt when is_binary(receipt_id) and receipt_id != "" ->
        Multi.new()
        |> Multi.run(:settle, fn _repo, _ ->
          Intents.mark_settled(intent, %{receipt: receipt_id})
        end)
        |> Multi.update(:mark, fn %{settle: settled} ->
          Receipt.mark_matched_changeset(receipt, settled.id, settled.business_id)
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{settle: settled}} -> {:ok, settled}
          {:error, _step, reason, _} -> {:error, reason}
        end

      _ ->
        :none
    end
  end

  def late_bind_await(%Intent{}), do: :none

  @doc false
  @spec find_clear_pending_match(String.t(), Decimal.t(), String.t() | nil) :: Receipt.t() | nil
  def find_clear_pending_match(business_id, amount, phone)
      when is_binary(business_id) and not is_nil(amount) do
    since = DateTime.add(DateTime.utc_now(), -30 * 60, :second)

    pending =
      from(r in Receipt,
        where:
          r.status == "unmatched" and
            (r.business_id == ^business_id or r.business_id in ^["unknown", ""]) and
            r.inserted_at >= ^since,
        order_by: [desc: r.inserted_at]
      )
      |> Repo.all()
      |> Enum.filter(&amounts_close?(&1.amount, amount))

    phone =
      case phone do
        p when is_binary(p) and p != "" -> p
        _ -> nil
      end

    cond do
      pending == [] ->
        nil

      is_binary(phone) ->
        phone_hits = Enum.filter(pending, &(&1.payer_msisdn == phone))

        case phone_hits do
          [one] -> one
          [one | _] -> one
          [] -> unique_or_nil(pending)
        end

      true ->
        unique_or_nil(pending)
    end
  end

  def find_clear_pending_match(_, _, _), do: nil

  defp unique_or_nil([one]), do: one
  defp unique_or_nil(_), do: nil

  defp amounts_close?(%Decimal{} = a, %Decimal{} = b) do
    Decimal.eq?(Decimal.round(a, 2), Decimal.round(b, 2))
  end

  defp amounts_close?(_, _), do: false

  defp unique_trans?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {_f, {_, opts}} ->
        opts[:constraint] == :unique or opts[:constraint_name] == :till_receipts_trans

      _ ->
        false
    end)
  end
end
