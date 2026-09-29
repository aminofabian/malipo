defmodule Malipo.Intents do
  @moduledoc """
  STK intent lifecycle — create, prompt, settle, fail, expire.

  Idempotency is reserved **before** any rail call: replaying
  `{business_id, idempotency_key}` returns the original intent.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Malipo.Intents.{Attempt, Intent}
  alias Malipo.Msisdn
  alias Malipo.Outbox
  alias Malipo.Merchants
  alias Malipo.Merchants.{Destination, SettlementRail}
  alias Malipo.Rails.Daraja
  alias Malipo.Rails.Daraja.Platform
  alias Malipo.Rails.Failure
  alias Malipo.Repo

  @default_ttl_seconds 90
  @till_await_prefix "till-await-"
  @till_await_ttl_seconds 15 * 60
  @till_await_replaced "Replaced by a new till payment wait"

  @doc "Synthetic checkout ids for Buy Goods awaits (no STK poll)."
  @spec till_await_checkout?(String.t() | nil) :: boolean()
  def till_await_checkout?(id) when is_binary(id), do: String.starts_with?(id, @till_await_prefix)
  def till_await_checkout?(_), do: false

  @doc "Fetch an intent by id."
  @spec get(Ecto.UUID.t()) :: Intent.t() | nil
  def get(id) when is_binary(id), do: Repo.get(Intent, id)

  @doc "Fetch an intent by id, raising if missing."
  @spec get!(Ecto.UUID.t()) :: Intent.t()
  def get!(id) when is_binary(id), do: Repo.get!(Intent, id)

  @doc """
  Create a pending intent, or return the existing one on idempotent replay.

  Does **not** call the rail — that is a separate step once credentials resolve.
  """
  @spec create(map()) ::
          {:ok, Intent.t()}
          | {:ok, Intent.t(), :replay}
          | {:error, Ecto.Changeset.t() | :invalid_phone}
  def create(attrs) when is_map(attrs) do
    with {:ok, params} <- build_create_params(attrs) do
      params = attribute_destination(params)

      case Repo.insert(Intent.create_changeset(params)) do
        {:ok, intent} ->
          {:ok, intent}

        {:error, %Ecto.Changeset{} = cs} ->
          case get_by_idempotency(params.business_id, params.idempotency_key) do
            %Intent{} = existing -> {:ok, existing, :replay}
            nil -> {:error, cs}
          end
      end
    end
  end

  @doc "Look up by business + idempotency key."
  @spec get_by_idempotency(String.t(), String.t()) :: Intent.t() | nil
  def get_by_idempotency(business_id, key)
      when is_binary(business_id) and is_binary(key) do
    Repo.get_by(Intent, business_id: business_id, idempotency_key: key)
  end

  @doc "Record a successful push: pending → prompted, plus an attempt row."
  @spec mark_prompted(Intent.t(), map()) ::
          {:ok, Intent.t()} | {:error, Ecto.Changeset.t() | term()}
  def mark_prompted(%Intent{} = intent, attrs) do
    now = DateTime.utc_now()
    attrs = stringify_keys(attrs)
    attrs = Map.put_new(attrs, "prompted_at", now)
    attempt_number = next_attempt_number(intent.id)
    known = atomize_known(attrs)

    intent_cs =
      case intent.status do
        "pending" -> Intent.mark_prompted_changeset(intent, known)
        "prompted" -> Intent.mark_reprompted_changeset(intent, known)
        _ -> Intent.mark_prompted_changeset(intent, known)
      end

    Multi.new()
    |> Multi.update(:intent, intent_cs)
    |> Multi.insert(
      :attempt,
      Attempt.create_changeset(intent.id, %{
        attempt_number: attempt_number,
        checkout_request_id: attrs["checkout_request_id"],
        merchant_request_id: attrs["merchant_request_id"],
        status: "sent",
        request_payload: attrs["request_payload"] || %{},
        response_payload: attrs["response_payload"] || %{}
      })
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{intent: intent}} -> {:ok, intent}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  @doc "Settle an intent with a provider receipt (writes outbox in the same txn)."
  @spec mark_settled(Intent.t(), map()) ::
          {:ok, Intent.t()} | {:error, Ecto.Changeset.t() | term()}
  def mark_settled(%Intent{} = intent, attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put_new("settled_at", DateTime.utc_now())
      |> atomize_known()
      |> Map.merge(fee_attrs(intent))

    Multi.new()
    |> Multi.update(:intent, Intent.mark_settled_changeset(intent, attrs))
    |> Multi.insert(:outbox, fn %{intent: settled} ->
      Outbox.build_for_intent(settled, "intent.settled")
    end)
    |> Multi.merge(fn %{outbox: row} ->
      Outbox.enqueue_dispatch(Multi.new(), row)
    end)
    |> Multi.run(:sweep, fn repo, %{intent: settled} ->
      case Malipo.Fees.sweep_for(settled) do
        nil -> {:ok, nil}
        sweep_attrs -> Malipo.Fees.insert_sweep(repo, sweep_attrs)
      end
    end)
    |> Multi.merge(fn results ->
      Malipo.Fees.enqueue_sweep(Multi.new(), Map.get(results, :sweep))
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{intent: settled}} -> {:ok, settled}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  @doc "Fail a pending/prompted intent (writes outbox in the same txn)."
  @spec mark_failed(Intent.t(), map()) ::
          {:ok, Intent.t()} | {:error, Ecto.Changeset.t() | term()}
  def mark_failed(%Intent{} = intent, attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put_new("failed_at", DateTime.utc_now())
      |> atomize_known()

    Multi.new()
    |> Multi.update(:intent, Intent.mark_failed_changeset(intent, attrs))
    |> Multi.insert(:outbox, fn %{intent: failed} ->
      Outbox.build_for_intent(failed, "intent.failed")
    end)
    |> Multi.merge(fn %{outbox: row} ->
      Outbox.enqueue_dispatch(Multi.new(), row)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{intent: failed}} -> {:ok, failed}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  @doc "Expire a pending/prompted intent (late settle still allowed; writes outbox)."
  @spec mark_expired(Intent.t(), map()) ::
          {:ok, Intent.t()} | {:error, Ecto.Changeset.t() | term()}
  def mark_expired(%Intent{} = intent, attrs \\ %{}) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put_new("expired_at", DateTime.utc_now())
      |> atomize_known()

    Multi.new()
    |> Multi.update(:intent, Intent.mark_expired_changeset(intent, attrs))
    |> Multi.insert(:outbox, fn %{intent: expired} ->
      Outbox.build_for_intent(expired, "intent.expired")
    end)
    |> Multi.merge(fn %{outbox: row} ->
      Outbox.enqueue_dispatch(Multi.new(), row)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{intent: expired}} -> {:ok, expired}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  @doc "Intents past expires_at that are still open."
  @spec list_expired_open(DateTime.t()) :: [Intent.t()]
  def list_expired_open(now \\ DateTime.utc_now())

  def list_expired_open(%DateTime{} = now) do
    from(i in Intent,
      where: i.status in ^["pending", "prompted"] and i.expires_at <= ^now,
      order_by: [asc: i.expires_at],
      limit: 200
    )
    |> Repo.all()
  end

  @doc "Recent intents newest-first (ops console)."
  @spec list_recent(non_neg_integer()) :: [Intent.t()]
  def list_recent(limit \\ 50) do
    from(i in Intent,
      order_by: [desc: i.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc "Recent intents for one business (Connect keys page)."
  @spec list_for_business(String.t(), non_neg_integer()) :: [Intent.t()]
  def list_for_business(business_id, limit \\ 5)
      when is_binary(business_id) and is_integer(limit) do
    from(i in Intent,
      where: i.business_id == ^business_id,
      order_by: [desc: i.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc "Open prompted intents due for a status poll (excludes Buy Goods till-awaits)."
  @spec list_prompted_for_poll(non_neg_integer()) :: [Intent.t()]
  def list_prompted_for_poll(limit \\ 100) do
    prefix = @till_await_prefix <> "%"

    from(i in Intent,
      where:
        i.status == "prompted" and
          (is_nil(i.checkout_request_id) or not like(i.checkout_request_id, ^prefix)),
      order_by: [asc: i.prompted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Open a Buy Goods await window — no STK push.

  Replaces any open till-await for the same `context.await_owner_id` (or all
  unowned awaits when the owner is blank). Then late-binds an unmatched
  till receipt if amount (+ phone) already arrived.
  """
  @spec open_till_await(map()) ::
          {:ok, Intent.t()}
          | {:ok, Intent.t(), :replay}
          | {:error, Ecto.Changeset.t() | :invalid_phone | :invalid_amount}
  def open_till_await(attrs) when is_map(attrs) do
    attrs = stringify_keys(attrs)

    with {:ok, params} <- build_till_await_params(attrs) do
      case get_by_idempotency(params.business_id, params.idempotency_key) do
        %Intent{} = existing ->
          {:ok, existing, :replay}

        nil ->
          insert_till_await(params)
      end
    end
  end

  @doc """
  Push a pending intent over Daraja.

  Credentials are caller-supplied (platform or BYO). On accept → prompted +
  attempt row. On classified failure → failed (no second prompt from a retry
  of this same intent without `resend`).
  """
  @spec push_stk(Intent.t(), map(), keyword()) ::
          {:ok, Intent.t()} | {:error, Failure.t() | Ecto.Changeset.t() | term()}
  def push_stk(intent, creds, opts \\ [])

  def push_stk(%Intent{status: "pending"} = intent, creds, opts) when is_list(opts) do
    do_push(intent, creds, opts, fail_on_error?: true)
  end

  def push_stk(%Intent{} = intent, _creds, _opts) do
    {:error, {:invalid_status, intent.status}}
  end

  @doc """
  Resend the STK prompt for a prompted intent (new attempt row).

  Does not fail the intent on a rail error — the previous prompt may still settle.
  """
  @spec resend_stk(Intent.t(), map(), keyword()) ::
          {:ok, Intent.t()} | {:error, Failure.t() | Ecto.Changeset.t() | term()}
  def resend_stk(intent, creds, opts \\ [])

  def resend_stk(%Intent{status: "prompted"} = intent, creds, opts) when is_list(opts) do
    do_push(intent, creds, opts, fail_on_error?: false)
  end

  def resend_stk(%Intent{status: "pending"} = intent, creds, opts) when is_list(opts) do
    push_stk(intent, creds, opts)
  end

  def resend_stk(%Intent{} = intent, _creds, _opts) do
    {:error, {:invalid_status, intent.status}}
  end

  @doc """
  Create (or replay) an intent and push STK when still pending.

  Idempotent replay of a non-pending intent returns the original without a
  second rail call.
  """
  @spec create_and_push(map(), keyword()) ::
          {:ok, Intent.t()}
          | {:ok, Intent.t(), :replay}
          | {:error, term()}
  def create_and_push(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    creds = Keyword.get(opts, :creds) || Platform.credentials()

    if is_nil(creds) do
      {:error, :credentials_missing}
    else
      attrs = maybe_merge_on_settled(attrs)

      case create(attrs) do
        {:ok, intent, :replay} ->
          case intent.status do
            "pending" ->
              case push_stk(intent, creds, opts) do
                {:ok, prompted} -> {:ok, prompted, :replay}
                other -> other
              end

            _ ->
              {:ok, intent, :replay}
          end

        {:ok, intent} ->
          push_stk(intent, creds, opts)

        other ->
          other
      end
    end
  end

  defp do_push(%Intent{} = intent, creds, opts, fail_on_error?: fail?) do
    callback = Keyword.get(opts, :callback_url) || Platform.callback_base()

    request = %{
      amount: intent.amount,
      phone: intent.payer_msisdn,
      account_reference: account_reference(intent),
      transaction_desc: transaction_desc(intent),
      callback_url: callback
    }

    case merchant_stk_request(intent, request) do
      {:error, reason} ->
        if fail? do
          _ =
            mark_failed(intent, %{
              failure_kind: Atom.to_string(reason),
              failure_message: failure_message_for(reason)
            })
        end

        {:error, reason}

      {:ok, request} ->
        do_daraja_push(intent, creds, request, fail?)
    end
  end

  defp do_daraja_push(intent, creds, request, fail?) do
    case Daraja.push(creds, request) do
      {:ok, result} ->
        mark_prompted(intent, %{
          checkout_request_id: result.checkout_request_id,
          merchant_request_id: result.merchant_request_id,
          request_payload: Map.drop(request, [:callback_url]),
          response_payload: result.raw
        })

      {:error, %Failure{} = failure} ->
        if fail? do
          _ =
            mark_failed(intent, %{
              failure_kind: Atom.to_string(failure.kind),
              failure_message: failure.message,
              failure_provider_code: failure.provider_code && to_string(failure.provider_code)
            })
        end

        {:error, failure}
    end
  end

  defp merchant_stk_request(%Intent{} = intent, request) do
    case SettlementRail.overrides_for_push(intent.context, intent.business_id) do
      {:ok, overrides} ->
        {:ok, Map.merge(request, overrides)}

      :skip ->
        {:ok, request}

      {:error, :destination_inactive} ->
        {:error, :destination_inactive}

      {:error, :invalid_destination} ->
        {:error, :destination_invalid}
    end
  end

  defp failure_message_for(:destination_inactive),
    do: "Confirm an activated settlement destination before collecting"

  defp failure_message_for(:destination_invalid),
    do: "Settlement destination is incomplete or invalid"

  defp failure_message_for(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp maybe_merge_on_settled(attrs) do
    attrs = stringify_keys(attrs)

    case Map.pop(attrs, "on_settled") do
      {nil, attrs} ->
        attrs

      {on_settled, attrs} when is_map(on_settled) ->
        ctx = Map.get(attrs, "context") || %{}
        Map.put(attrs, "context", Map.put(ctx, "on_settled", on_settled))

      {_other, attrs} ->
        attrs
    end
  end

  @doc """
  Poll one prompted intent against Daraja and settle or fail.

  Pending / inconclusive results leave the row untouched for the next tick.
  """
  @spec reconcile_prompted(Intent.t(), map()) ::
          {:ok, Intent.t()} | {:pending, Intent.t()} | {:error, term()}
  def reconcile_prompted(
        %Intent{status: "prompted", checkout_request_id: checkout_id} = intent,
        creds
      )
      when is_binary(checkout_id) do
    if till_await_checkout?(checkout_id) do
      {:pending, intent}
    else
      do_reconcile_prompted(intent, creds, checkout_id)
    end
  end

  def reconcile_prompted(%Intent{} = intent, _creds), do: {:pending, intent}

  defp do_reconcile_prompted(intent, creds, checkout_id) do
    case Daraja.query(creds, checkout_id) do
      {:ok, %{outcome: :success, receipt: receipt}} when is_binary(receipt) and receipt != "" ->
        mark_settled(intent, %{receipt: receipt})

      {:ok, %{outcome: :pending}} ->
        {:pending, intent}

      {:ok, %{outcome: :success}} ->
        {:pending, intent}

      {:error, %Failure{kind: kind}}
      when kind in [:pending, :inconclusive, :provider_unavailable] ->
        {:pending, intent}

      {:error, %Failure{} = failure} ->
        case mark_failed(intent, %{
               failure_kind: Atom.to_string(failure.kind),
               failure_message: failure.message,
               failure_provider_code: failure.provider_code && to_string(failure.provider_code)
             }) do
          {:ok, failed} -> {:ok, failed}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp account_reference(%Intent{context: ctx, business_id: biz}) when is_map(ctx) do
    ctx["description"] || ctx["await_owner_id"] || ctx["id"] || biz
  end

  defp account_reference(%Intent{business_id: biz}), do: biz

  defp transaction_desc(%Intent{context: %{"type" => type}}) when is_binary(type), do: type
  defp transaction_desc(_), do: "Payment"

  # Snapshot the destination that will receive this intent, so per-destination
  # totals can be computed later even after the merchant switches defaults.
  defp attribute_destination(%{context: ctx, business_id: business_id} = params)
       when is_binary(business_id) do
    ctx = ctx || %{}

    if ctx["settlement_destination_id"] do
      params
    else
      case Merchants.get_active_destination(business_id) do
        %Destination{id: id} when is_binary(id) ->
          %{params | context: Map.put(ctx, "settlement_destination_id", id)}

        _ ->
          params
      end
    end
  end

  defp attribute_destination(params), do: params

  defp build_create_params(attrs) do
    attrs = stringify_keys(attrs)

    with {:ok, msisdn} <- Msisdn.normalise(attrs["payer_msisdn"]) do
      expires_at =
        case attrs["expires_at"] do
          %DateTime{} = dt -> dt
          _ -> DateTime.add(DateTime.utc_now(), @default_ttl_seconds, :second)
        end

      amount =
        case attrs["amount"] do
          %Decimal{} = d -> d
          n when is_integer(n) or is_float(n) -> Decimal.new(n)
          s when is_binary(s) -> Decimal.new(s)
          other -> other
        end

      context = merge_settlement_into_context(attrs)

      {:ok,
       %{
         business_id: attrs["business_id"],
         idempotency_key: attrs["idempotency_key"],
         rail: attrs["rail"] || "daraja",
         amount: amount,
         currency: attrs["currency"] || "KES",
         payer_msisdn: msisdn,
         context: context,
         expires_at: expires_at
       }}
    end
  end

  defp merge_settlement_into_context(attrs) do
    ctx =
      case attrs["context"] do
        %{} = c -> c
        _ -> %{}
      end

    dest =
      attrs["settlement_destination"] ||
        attrs["destination"] ||
        ctx["settlement_destination"] ||
        ctx["destination"]

    party_b = attrs["party_b"] || attrs["partyB"] || ctx["party_b"] || ctx["partyB"]

    ctx =
      if is_map(dest) do
        Map.put(ctx, "settlement_destination", dest)
      else
        ctx
      end

    if is_binary(party_b) and party_b != "" do
      Map.put(ctx, "party_b", party_b)
    else
      ctx
    end
  end

  defp build_till_await_params(attrs) do
    amount =
      case attrs["amount"] do
        %Decimal{} = d -> d
        n when is_integer(n) or is_float(n) -> Decimal.new(n)
        s when is_binary(s) and s != "" -> Decimal.new(s)
        _ -> nil
      end

    cond do
      is_nil(amount) or Decimal.compare(amount, 0) != :gt ->
        {:error, :invalid_amount}

      not is_binary(attrs["business_id"]) or attrs["business_id"] == "" ->
        {:error,
         Intent.create_till_await_changeset(%{amount: amount || Decimal.new("1")})
         |> Ecto.Changeset.add_error(:business_id, "can't be blank")}

      true ->
        phone =
          case attrs["payer_msisdn"] || attrs["phone_number"] do
            nil ->
              ""

            "" ->
              ""

            raw ->
              case Msisdn.normalise(raw) do
                {:ok, msisdn} -> msisdn
                {:error, :invalid_phone} -> :invalid
              end
          end

        if phone == :invalid do
          {:error, :invalid_phone}
        else
          checkout = @till_await_prefix <> Ecto.UUID.generate()

          idem =
            case attrs["idempotency_key"] do
              key when is_binary(key) and key != "" -> key
              _ -> checkout
            end

          context =
            case attrs["context"] do
              %{} = ctx -> ctx
              _ -> %{}
            end

          context =
            case attrs["await_owner_id"] do
              owner when is_binary(owner) and owner != "" ->
                Map.put_new(context, "await_owner_id", owner)

              _ ->
                context
            end

          expires_at =
            case attrs["expires_at"] do
              %DateTime{} = dt -> dt
              _ -> DateTime.add(DateTime.utc_now(), @till_await_ttl_seconds, :second)
            end

          {:ok,
           %{
             business_id: attrs["business_id"],
             idempotency_key: idem,
             rail: "daraja",
             amount: amount,
             currency: attrs["currency"] || "KES",
             payer_msisdn: phone,
             context: context,
             expires_at: expires_at,
             checkout_request_id: checkout,
             prompted_at: DateTime.utc_now()
           }}
        end
    end
  end

  defp insert_till_await(params) do
    Multi.new()
    |> Multi.run(:replace, fn _repo, _ ->
      replace_open_till_awaits(params.business_id, await_owner(params.context))
      {:ok, :replaced}
    end)
    |> Multi.insert(:intent, Intent.create_till_await_changeset(params))
    |> Repo.transaction()
    |> case do
      {:ok, %{intent: intent}} ->
        case Malipo.Till.late_bind_await(intent) do
          {:ok, settled} -> {:ok, settled}
          :none -> {:ok, intent}
          {:error, reason} -> {:error, reason}
        end

      {:error, :intent, %Ecto.Changeset{} = cs, _} ->
        case get_by_idempotency(params.business_id, params.idempotency_key) do
          %Intent{} = existing -> {:ok, existing, :replay}
          nil -> {:error, cs}
        end

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  defp replace_open_till_awaits(business_id, owner) when is_binary(business_id) do
    since = DateTime.add(DateTime.utc_now(), -@till_await_ttl_seconds, :second)
    prefix = @till_await_prefix <> "%"

    from(i in Intent,
      where:
        i.business_id == ^business_id and
          i.status == "prompted" and
          i.inserted_at >= ^since and
          like(i.checkout_request_id, ^prefix),
      order_by: [desc: i.inserted_at]
    )
    |> Repo.all()
    |> Enum.filter(&same_await_owner?(&1, owner))
    |> Enum.each(fn prior ->
      _ =
        mark_failed(prior, %{
          failure_kind: "replaced",
          failure_message: @till_await_replaced
        })
    end)
  end

  defp await_owner(%{"await_owner_id" => owner}) when is_binary(owner) and owner != "", do: owner
  defp await_owner(_), do: nil

  defp same_await_owner?(%Intent{context: ctx}, owner) do
    prior = is_map(ctx) && ctx["await_owner_id"]

    cond do
      is_nil(prior) or prior == "" or is_nil(owner) -> true
      true -> prior == owner
    end
  end

  defp next_attempt_number(intent_id) do
    from(a in Attempt,
      where: a.intent_id == ^intent_id,
      select: coalesce(max(a.attempt_number), 0)
    )
    |> Repo.one()
    |> Kernel.+(1)
  end

  defp fee_attrs(%Intent{amount: amount}) do
    case Malipo.Fees.quote(amount) do
      {:ok, %{fee: fee, net: net}} -> %{fee_amount: fee, net_amount: net}
      _ -> %{}
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} when is_binary(k) -> {k, v}
    end)
  end

  defp atomize_known(map) do
    allowed = %{
      "checkout_request_id" => :checkout_request_id,
      "merchant_request_id" => :merchant_request_id,
      "prompted_at" => :prompted_at,
      "settled_at" => :settled_at,
      "failed_at" => :failed_at,
      "expired_at" => :expired_at,
      "receipt" => :receipt,
      "failure_kind" => :failure_kind,
      "failure_message" => :failure_message,
      "failure_provider_code" => :failure_provider_code,
      "request_payload" => :request_payload,
      "response_payload" => :response_payload,
      "fee_amount" => :fee_amount,
      "net_amount" => :net_amount
    }

    Map.new(map, fn {k, v} ->
      key =
        cond do
          is_atom(k) -> k
          is_map_key(allowed, k) -> allowed[k]
          true -> raise ArgumentError, "unknown intent attr: #{inspect(k)}"
        end

      {key, v}
    end)
  end
end
