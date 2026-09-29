defmodule Malipo.Till.Receipt do
  @moduledoc """
  Inbound Daraja C2B money — unmatched until bound to an intent / sale.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Malipo.Intents.Intent

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @statuses ~w(unmatched matched ignored)

  schema "till_receipts" do
    field :rail, :string, default: "daraja"
    field :trans_id, :string
    field :shortcode, :string
    field :business_id, :string
    field :amount, :decimal
    field :currency, :string, default: "KES"
    field :payer_msisdn, :string
    field :payer_name, :string
    field :bill_ref, :string
    field :transaction_type, :string
    field :trans_time, :string
    field :status, :string, default: "unmatched"
    field :raw_payload, :map, default: %{}

    belongs_to :matched_intent, Intent, foreign_key: :matched_intent_id

    timestamps()
  end

  @type t :: %__MODULE__{}

  def statuses, do: @statuses

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :rail,
      :trans_id,
      :shortcode,
      :business_id,
      :amount,
      :currency,
      :payer_msisdn,
      :payer_name,
      :bill_ref,
      :transaction_type,
      :trans_time,
      :raw_payload
    ])
    |> validate_required([:trans_id, :amount])
    |> validate_number(:amount, greater_than: 0)
    |> put_change(:status, "unmatched")
    |> put_change(:rail, "daraja")
    |> unique_constraint([:rail, :trans_id], name: :till_receipts_trans)
  end

  def mark_matched_changeset(%__MODULE__{} = row, intent_id, business_id \\ nil)
      when is_binary(intent_id) do
    row
    |> change()
    |> put_change(:status, "matched")
    |> put_change(:matched_intent_id, intent_id)
    |> then(fn cs ->
      if is_binary(business_id) and business_id != "",
        do: put_change(cs, :business_id, business_id),
        else: cs
    end)
  end
end
