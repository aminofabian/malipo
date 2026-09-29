defmodule Malipo.Fees do
  @moduledoc """
  Transaction fee schedule and platform settings.

  Bands are whole-KES inclusive ranges with a flat fee. The schedule is
  editable from the super-admin (`/admin/fees`) and quoted per settlement.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Malipo.Fees.{Band, Config, Sweep, SweepWorker}
  alias Malipo.Rails.Failure
  alias Malipo.Repo

  # amount_from, amount_to, fee (KES) — the shipped defaults.
  @default_bands [
    {1, 10, 0},
    {11, 49, 1},
    {50, 499, 6},
    {500, 999, 10},
    {1000, 1499, 15},
    {1500, 2499, 20},
    {2500, 3499, 25},
    {3500, 4999, 30},
    {5000, 7499, 40},
    {7500, 9999, 45},
    {10000, 14999, 50},
    {15000, 19999, 55},
    {20000, 34999, 80},
    {35000, 49999, 105},
    {50000, 149_999, 130},
    {150_000, 249_999, 160},
    {250_000, 349_999, 195},
    {350_000, 549_999, 230},
    {550_000, 749_999, 275},
    {750_000, 999_999, 320}
  ]

  @doc "Insert the default schedule and config if the tables are empty."
  def ensure_defaults do
    if Repo.aggregate(Band, :count) == 0 do
      seed_default_bands()
    end

    _ = get_config!()
    :ok
  end

  defp seed_default_bands do
    now = DateTime.utc_now()

    rows =
      @default_bands
      |> Enum.with_index()
      |> Enum.map(fn {{from, to, fee}, i} ->
        %{
          id: Ecto.UUID.generate(),
          amount_from: from,
          amount_to: to,
          fee: fee,
          position: i,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(Band, rows)
  end

  @doc "All bands, ordered by lower bound."
  def list_bands do
    ensure_defaults()
    Repo.all(from b in Band, order_by: [asc: b.amount_from, asc: b.position])
  end

  @doc "Singleton config row (creates an empty one if missing)."
  def get_config! do
    case Repo.one(from c in Config, limit: 1) do
      %Config{} = row ->
        row

      nil ->
        {:ok, row} = %Config{} |> Config.changeset(%{}) |> Repo.insert()
        row
    end
  end

  @doc "Whether fees are enabled."
  def enabled?, do: get_config!().enabled

  @doc """
  Quote the fee and net for a payment amount.

  Uses a step lookup: the band with the greatest `amount_from` that is `<= amount`.
  Amounts below the first band are fee-free.
  """
  @spec quote(Decimal.t() | integer() | String.t()) ::
          {:ok, %{fee: Decimal.t(), net: Decimal.t()}} | {:error, :invalid_amount}
  def quote(amount) do
    ensure_defaults()

    case to_decimal(amount) do
      {:ok, dec} ->
        int = dec |> Decimal.round(0, :floor) |> Decimal.to_integer()
        band = band_for(int)
        fee = if band, do: Decimal.new(band.fee), else: Decimal.new(0)
        {:ok, %{fee: fee, net: Decimal.sub(dec, fee)}}

      :error ->
        {:error, :invalid_amount}
    end
  end

  @doc "Convenience: fee only."
  def fee_for(amount) do
    # `quote/1` is also an `Ecto.Query` macro; call the local function explicitly.
    case __MODULE__.quote(amount) do
      {:ok, %{fee: fee}} -> fee
      _ -> Decimal.new(0)
    end
  end

  @doc """
  Replace the whole schedule in one transaction.

  Takes a list of maps with `amount_from`, `amount_to`, `fee` (strings or ints).
  """
  def replace_bands(list) when is_list(list) do
    bands =
      list
      |> Enum.with_index()
      |> Enum.map(fn {attrs, i} -> band_attrs(attrs, i) end)

    with :ok <- validate_bands(bands) do
      now = DateTime.utc_now()

      rows =
        Enum.map(bands, fn attrs ->
          attrs
          |> Map.put(:id, Ecto.UUID.generate())
          |> Map.put(:inserted_at, now)
          |> Map.put(:updated_at, now)
        end)

      Repo.transaction(fn ->
        Repo.delete_all(Band)
        if rows != [], do: Repo.insert_all(Band, rows)
        list_bands()
      end)
    end
  end

  defp validate_bands(bands) do
    problems =
      bands
      |> Enum.flat_map(fn attrs ->
        case Band.changeset(attrs) do
          %{valid?: true} -> []
          cs -> Enum.map(cs.errors, fn {field, {msg, _}} -> "#{field} #{msg}" end)
        end
      end)

    case problems do
      [] -> :ok
      _ -> {:error, Enum.join(problems, "; ")}
    end
  end

  defp band_attrs(attrs, index) do
    %{
      amount_from: to_int(attrs["amount_from"] || attrs[:amount_from]),
      amount_to: to_int(attrs["amount_to"] || attrs[:amount_to]),
      fee: to_int(attrs["fee"] || attrs[:fee]),
      position: index
    }
  end

  @doc "Update the singleton config (rates + fee destination)."
  def update_config(attrs) when is_map(attrs) do
    get_config!()
    |> Config.changeset(stringify(attrs))
    |> Repo.update()
  end

  @doc "How collected fees move: manual (default) or auto."
  def sweep_mode, do: get_config!().sweep_mode

  @doc """
  Build sweep attrs for a settled intent, or `nil` when nothing should move
  (fees off, zero fee, or no destination configured).
  """
  @spec sweep_for(map()) :: map() | nil
  def sweep_for(%{id: intent_id, business_id: business_id, fee_amount: amount} = intent) do
    currency = Map.get(intent, :currency) || "KES"

    with true <- enabled?(),
         true <- positive?(amount),
         %{} = dest <- destination() do
      %{
        intent_id: intent_id,
        business_id: business_id,
        amount: amount,
        currency: currency,
        status: "pending",
        mode: sweep_mode(),
        destination_kind: dest.kind,
        destination_till: Map.get(dest, :till_number),
        destination_paybill: Map.get(dest, :paybill_number),
        destination_account: Map.get(dest, :account_number),
        destination_name: Map.get(dest, :display_name),
        next_attempt_at: DateTime.utc_now()
      }
    else
      _ -> nil
    end
  end

  @doc "Insert a sweep inside the settlement transaction (`Multi.run`)."
  def insert_sweep(repo, attrs) when is_map(attrs), do: repo.insert(Sweep.create_changeset(attrs))

  @doc "Enqueue the sweep worker in the same Multi (no-op for a nil sweep)."
  def enqueue_sweep(%Multi{} = multi, %Sweep{id: id}) do
    Oban.insert(multi, :fee_sweep, SweepWorker.new(%{"sweep_id" => id}))
  end

  def enqueue_sweep(%Multi{} = multi, _), do: multi

  @doc "Fetch a sweep by id."
  def get_sweep(id) when is_binary(id), do: Repo.get(Sweep, id)

  @doc "Recent sweeps, newest first."
  def list_sweeps(limit \\ 50) do
    from(s in Sweep, order_by: [desc: s.inserted_at], limit: ^limit) |> Repo.all()
  end

  @doc "Sweeps needing attention (`pending`/`awaiting`/`sent`)."
  def list_open_sweeps do
    from(s in Sweep,
      where: s.status in ^Sweep.open_statuses(),
      order_by: [asc: s.inserted_at]
    )
    |> Repo.all()
  end

  # ── sweep lifecycle ────────────────────────────────────────────────

  @doc """
  Drive a pending sweep one step forward.

  `manual` sweeps are left for an operator (`awaiting`). `auto` sweeps attempt
  a rail transfer; retryable failures return `{:error, reason}` so Oban retries.
  """
  @spec process_sweep(Sweep.t()) :: :ok | {:error, term()}
  def process_sweep(%Sweep{mode: "manual"} = sweep) do
    case sweep
         |> Sweep.mark_awaiting_changeset("Manual mode — send to the fee account")
         |> Repo.update() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def process_sweep(%Sweep{mode: "auto"} = sweep) do
    with %{} = creds <- Malipo.Rails.Daraja.Platform.credentials(),
         {:ok, rail} <- Malipo.Rails.Registry.fetch(:daraja) do
      transfer(rail, sweep, creds)
    else
      _ -> park(sweep, "Auto mode — rail not configured")
    end
  end

  def process_sweep(%Sweep{}), do: :ok

  defp park(%Sweep{} = sweep, reason) do
    case sweep |> Sweep.mark_awaiting_changeset(reason) |> Repo.update() do
      {:ok, _} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp transfer(rail, %Sweep{} = sweep, creds) do
    case rail.transfer(creds, transfer_request(sweep)) do
      {:ok, %{conversation_id: conversation_id} = result} ->
        sweep
        |> Sweep.mark_sent_changeset(%{
          provider_conversation_id: conversation_id,
          originator_conversation_id: result[:originator_conversation_id]
        })
        |> Repo.update()
        |> case do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, %Failure{kind: :bad_credentials, message: message}} ->
        park(sweep, "Auto mode — #{message}")

      {:error, %Failure{retryable?: true} = failure} ->
        {:error, "#{failure.kind}: #{failure.message}"}

      {:error, %Failure{} = failure} ->
        sweep
        |> Sweep.mark_failed_changeset(failure.kind, failure.message)
        |> Repo.update()
        |> case do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp transfer_request(%Sweep{} = sweep) do
    base = Malipo.Rails.Daraja.Platform.callback_base() || ""

    %{
      amount: sweep.amount,
      destination: %{
        kind: sweep.destination_kind,
        till: sweep.destination_till,
        paybill: sweep.destination_paybill,
        account: sweep.destination_account
      },
      account_reference: sweep.destination_account || "FEES",
      remarks: "Malipo fees",
      result_url: String.trim_trailing(base, "/") <> "/webhooks/daraja/b2b/result",
      timeout_url: String.trim_trailing(base, "/") <> "/webhooks/daraja/b2b/timeout"
    }
  end

  @doc "Operator marks a manual sweep as settled (money moved offline)."
  def mark_sweep_settled(%Sweep{} = sweep, attrs \\ %{}) do
    sweep |> Sweep.mark_settled_changeset(attrs) |> Repo.update()
  end

  @doc "Operator abandons a manual sweep."
  def mark_sweep_skipped(%Sweep{} = sweep, reason) do
    sweep |> Sweep.mark_skipped_changeset(reason) |> Repo.update()
  end

  @doc """
  Finalise a sweep from the provider result/timeout webhook.

  Returns `{:ok, sweep | nil}` — `nil` when nothing matched the conversation id.
  """
  @spec finalize_sweep_webhook(String.t(), map()) :: {:ok, Sweep.t() | nil}
  def finalize_sweep_webhook(kind, payload) when is_map(payload) do
    result = extract_result(payload)

    case find_sweep(result) do
      nil ->
        {:ok, nil}

      %Sweep{status: status} = sweep when status in ["settled", "failed", "skipped"] ->
        {:ok, sweep}

      %Sweep{} = sweep ->
        {:ok, apply_transfer_outcome(kind, sweep, result)}
    end
  end

  defp apply_transfer_outcome(_kind, sweep, %{code: code} = result) when code in ["0", "00"] do
    {:ok, updated} =
      sweep
      |> Sweep.mark_settled_changeset(%{receipt: result[:receipt]})
      |> Repo.update()

    updated
  end

  defp apply_transfer_outcome(kind, sweep, result) do
    reason = result[:description] || "transfer failed"
    kind = if kind == "b2b_timeout", do: :timeout, else: :unknown

    {:ok, updated} = sweep |> Sweep.mark_failed_changeset(kind, reason) |> Repo.update()
    updated
  end

  defp find_sweep(%{} = result) do
    key = result[:conversation_id] || result[:originator_conversation_id]

    if is_binary(key) and key != "" do
      Repo.one(
        from(s in Sweep,
          where: s.provider_conversation_id == ^key or s.originator_conversation_id == ^key,
          order_by: [desc: s.inserted_at],
          limit: 1
        )
      )
    end
  end

  defp extract_result(payload) do
    result =
      payload["Result"] || payload["result"] ||
        get_in(payload, ["Body", "Result"]) || get_in(payload, ["Body", "result"]) || %{}

    %{
      code: text(result["ResultCode"] || result["resultCode"]),
      description: result["ResultDesc"] || result["resultDesc"],
      conversation_id: result["ConversationID"] || result["conversationID"],
      originator_conversation_id:
        result["OriginatorConversationID"] || result["originatorConversationID"],
      receipt: result["TransactionID"] || result["transactionID"]
    }
  end

  defp text(nil), do: nil
  defp text(v) when is_binary(v), do: v
  defp text(v) when is_integer(v), do: Integer.to_string(v)
  defp text(v), do: to_string(v)

  defp positive?(%Decimal{} = d), do: Decimal.compare(d, 0) == :gt
  defp positive?(n) when is_integer(n), do: n > 0
  defp positive?(n) when is_float(n), do: n > 0
  defp positive?(_), do: false

  @doc "Where collected fees should be received, or nil when unset."
  def destination do
    row = get_config!()

    case row.fee_destination_kind do
      "till" ->
        %{
          kind: "till",
          till_number: row.fee_destination_till,
          display_name: row.fee_destination_name
        }

      "paybill" ->
        %{
          kind: "paybill",
          paybill_number: row.fee_destination_paybill,
          account_number: row.fee_destination_account,
          display_name: row.fee_destination_name
        }

      "bank" ->
        %{
          kind: "bank",
          paybill_number: row.fee_destination_paybill,
          account_number: row.fee_destination_account,
          bank_id: row.fee_destination_bank_id,
          display_name: row.fee_destination_name
        }

      _ ->
        nil
    end
  end

  @doc "Read-only view for the public API and marketing (no secrets)."
  def public_view do
    row = get_config!()

    %{
      "enabled" => row.enabled,
      "currency" => "KES",
      "sms_rate" => cents_to_kes(row.sms_rate),
      "whatsapp_rate" => cents_to_kes(row.whatsapp_rate),
      "bands" =>
        list_bands()
        |> Enum.map(fn b ->
          %{"from" => b.amount_from, "to" => b.amount_to, "fee" => b.fee}
        end)
    }
  end

  # --- helpers ---

  defp cents_to_kes(nil), do: "0.00"

  defp cents_to_kes(cents) when is_integer(cents) do
    cents
    |> Decimal.new()
    |> Decimal.div(Decimal.new(100))
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  defp band_for(amount_int) do
    Repo.one(
      from b in Band,
        where: b.amount_from <= ^amount_int,
        order_by: [desc: b.amount_from, desc: b.position],
        limit: 1
    )
  end

  defp to_decimal(%Decimal{} = d), do: {:ok, d}
  defp to_decimal(n) when is_integer(n), do: {:ok, Decimal.new(n)}
  defp to_decimal(n) when is_float(n), do: {:ok, Decimal.from_float(n)}

  defp to_decimal(s) when is_binary(s) do
    case Decimal.parse(s) do
      {d, ""} -> {:ok, d}
      _ -> :error
    end
  end

  defp to_decimal(_), do: :error

  defp to_int(nil), do: 0
  defp to_int(n) when is_integer(n), do: n

  defp to_int(s) when is_binary(s) do
    case Integer.parse(String.trim(s)) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp stringify(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
