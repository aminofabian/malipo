defmodule Malipo.Intents.Intent do
  @moduledoc """
  STK intent — one request for money to move over a rail.

  State machine (enforced in changesets + DB trigger):

      pending → prompted → settled
                       ↘ failed
                       ↘ expired

  `failed` / `expired` may still move to `settled` on a late provider receipt.
  `settled` is terminal forever.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Malipo.Intents.Attempt

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @statuses ~w(pending prompted settled failed expired)
  @terminal ~w(settled failed expired)

  schema "intents" do
    field :business_id, :string
    field :idempotency_key, :string
    field :rail, :string, default: "daraja"

    field :amount, :decimal
    field :currency, :string, default: "KES"
    field :payer_msisdn, :string

    field :status, :string, default: "pending"
    field :context, :map, default: %{}

    field :checkout_request_id, :string
    field :merchant_request_id, :string
    field :receipt, :string

    field :fee_amount, :decimal
    field :net_amount, :decimal

    field :failure_kind, :string
    field :failure_message, :string
    field :failure_provider_code, :string

    field :expires_at, :utc_datetime_usec
    field :prompted_at, :utc_datetime_usec
    field :settled_at, :utc_datetime_usec
    field :failed_at, :utc_datetime_usec
    field :expired_at, :utc_datetime_usec

    has_many :attempts, Attempt

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc false
  def statuses, do: @statuses

  @doc false
  def terminal?(status) when is_binary(status), do: status in @terminal

  @doc "Changeset for creating a pending intent (idempotency reserved before push)."
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :business_id,
      :idempotency_key,
      :rail,
      :amount,
      :currency,
      :payer_msisdn,
      :context,
      :expires_at
    ])
    |> validate_required([
      :business_id,
      :idempotency_key,
      :amount,
      :currency,
      :payer_msisdn,
      :expires_at
    ])
    |> validate_number(:amount, greater_than: 0)
    |> validate_length(:currency, is: 3)
    |> validate_length(:idempotency_key, min: 8, max: 191)
    |> validate_inclusion(:rail, ["daraja"])
    |> put_change(:status, "pending")
    |> unique_constraint([:business_id, :idempotency_key], name: :intents_idem)
  end

  @doc """
  Buy Goods await — no STK. Inserted already `prompted` with a synthetic
  `till-await-…` checkout id so C2B matching can settle it.
  """
  def create_till_await_changeset(attrs) do
    now = DateTime.utc_now()

    %__MODULE__{}
    |> cast(attrs, [
      :business_id,
      :idempotency_key,
      :rail,
      :amount,
      :currency,
      :payer_msisdn,
      :context,
      :expires_at,
      :checkout_request_id,
      :prompted_at
    ])
    |> validate_required([
      :business_id,
      :idempotency_key,
      :amount,
      :currency,
      :expires_at,
      :checkout_request_id
    ])
    |> validate_number(:amount, greater_than: 0)
    |> validate_length(:currency, is: 3)
    |> validate_length(:idempotency_key, min: 8, max: 191)
    |> validate_inclusion(:rail, ["daraja"])
    |> then(fn cs ->
      case get_field(cs, :payer_msisdn) do
        nil -> put_change(cs, :payer_msisdn, "")
        _ -> cs
      end
    end)
    |> then(fn cs ->
      case get_field(cs, :prompted_at) do
        nil -> put_change(cs, :prompted_at, now)
        _ -> cs
      end
    end)
    |> put_change(:status, "prompted")
    |> unique_constraint([:business_id, :idempotency_key], name: :intents_idem)
  end

  @doc "pending → prompted after a successful rail push."
  def mark_prompted_changeset(%__MODULE__{status: "pending"} = intent, attrs) do
    intent
    |> cast(attrs, [:checkout_request_id, :merchant_request_id, :prompted_at])
    |> validate_required([:checkout_request_id, :prompted_at])
    |> put_change(:status, "prompted")
  end

  def mark_prompted_changeset(%__MODULE__{} = intent, _attrs) do
    intent
    |> change()
    |> add_error(:status, "cannot prompt from #{intent.status}")
  end

  @doc "prompted → prompted on resend (new CheckoutRequestID, same intent)."
  def mark_reprompted_changeset(%__MODULE__{status: "prompted"} = intent, attrs) do
    intent
    |> cast(attrs, [:checkout_request_id, :merchant_request_id, :prompted_at])
    |> validate_required([:checkout_request_id, :prompted_at])
  end

  def mark_reprompted_changeset(%__MODULE__{} = intent, _attrs) do
    intent
    |> change()
    |> add_error(:status, "cannot resend from #{intent.status}")
  end

  @doc "prompted | failed | expired → settled on a provider receipt."
  def mark_settled_changeset(%__MODULE__{status: status} = intent, attrs)
      when status in ~w(prompted failed expired) do
    intent
    |> cast(attrs, [:receipt, :settled_at, :checkout_request_id, :merchant_request_id, :fee_amount, :net_amount])
    |> validate_required([:receipt, :settled_at])
    |> put_change(:status, "settled")
    |> put_change(:failure_kind, nil)
    |> put_change(:failure_message, nil)
    |> put_change(:failure_provider_code, nil)
    |> unique_constraint([:rail, :receipt], name: :intents_receipt)
  end

  def mark_settled_changeset(%__MODULE__{} = intent, _attrs) do
    intent
    |> change()
    |> add_error(:status, "cannot settle from #{intent.status}")
  end

  @doc "pending | prompted → failed."
  def mark_failed_changeset(%__MODULE__{status: status} = intent, attrs)
      when status in ~w(pending prompted) do
    intent
    |> cast(attrs, [
      :failure_kind,
      :failure_message,
      :failure_provider_code,
      :failed_at
    ])
    |> validate_required([:failure_kind, :failure_message, :failed_at])
    |> put_change(:status, "failed")
  end

  def mark_failed_changeset(%__MODULE__{} = intent, _attrs) do
    intent
    |> change()
    |> add_error(:status, "cannot fail from #{intent.status}")
  end

  @doc "pending | prompted → expired (local UX expiry; late settle still allowed)."
  def mark_expired_changeset(%__MODULE__{status: status} = intent, attrs)
      when status in ~w(pending prompted) do
    intent
    |> cast(attrs, [:expired_at, :failure_message])
    |> validate_required([:expired_at])
    |> put_change(:status, "expired")
    |> put_change(:failure_kind, "expired")
  end

  def mark_expired_changeset(%__MODULE__{} = intent, _attrs) do
    intent
    |> change()
    |> add_error(:status, "cannot expire from #{intent.status}")
  end
end
