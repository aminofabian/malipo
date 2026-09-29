defmodule Malipo.Fees.Sweep do
  @moduledoc """
  One movement of a collected service fee to the configured fee account.

  A sweep is written in the same transaction that settles an intent, then an Oban
  worker drives it forward. `mode` is snapshotted from the fee settings so a
  config change does not strand an in-flight sweep.

  Statuses:
  * `pending`  — recorded, worker not yet run
  * `awaiting` — needs an operator (manual mode, or auto without rail operator credentials)
  * `sent`     — transfer accepted by the provider, awaiting the result callback
  * `settled`  — money confirmed moved
  * `failed`   — transfer rejected / exhausted retries
  * `skipped`  — nothing to move (fees off, zero fee, or no destination)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @statuses ~w(pending awaiting sent settled failed skipped)
  @modes ~w(manual auto)
  @open_statuses ~w(pending awaiting sent)

  schema "fee_sweeps" do
    field :intent_id, :binary_id
    field :business_id, :string

    field :amount, :decimal
    field :currency, :string, default: "KES"

    field :status, :string, default: "pending"
    field :mode, :string, default: "manual"

    field :destination_kind, :string
    field :destination_till, :string
    field :destination_paybill, :string
    field :destination_account, :string
    field :destination_name, :string

    field :provider_conversation_id, :string
    field :originator_conversation_id, :string
    field :receipt, :string
    field :failure_kind, :string
    field :failure_message, :string

    field :attempts, :integer, default: 0
    field :next_attempt_at, :utc_datetime_usec
    field :sent_at, :utc_datetime_usec
    field :settled_at, :utc_datetime_usec

    timestamps()
  end

  @type t :: %__MODULE__{}

  def statuses, do: @statuses
  def modes, do: @modes
  def open_statuses, do: @open_statuses

  @doc "Build a sweep from settlement attrs. Caller inserts it in the settle txn."
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :intent_id,
      :business_id,
      :amount,
      :currency,
      :status,
      :mode,
      :destination_kind,
      :destination_till,
      :destination_paybill,
      :destination_account,
      :destination_name,
      :next_attempt_at
    ])
    |> validate_required([:amount, :currency, :status, :mode])
    |> validate_number(:amount, greater_than: 0)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:mode, @modes)
    |> unique_constraint(:intent_id)
  end

  def mark_awaiting_changeset(%__MODULE__{} = sweep, reason \\ "Awaiting operator") do
    sweep
    |> change(status: "awaiting", failure_message: reason)
  end

  def mark_sent_changeset(%__MODULE__{} = sweep, attrs) do
    sweep
    |> cast(attrs, [:provider_conversation_id, :originator_conversation_id])
    |> put_change(:status, "sent")
    |> put_change(:sent_at, DateTime.utc_now())
    |> put_change(:failure_kind, nil)
    |> put_change(:failure_message, nil)
  end

  def mark_settled_changeset(%__MODULE__{} = sweep, attrs \\ %{}) do
    sweep
    |> cast(attrs, [:receipt])
    |> put_change(:status, "settled")
    |> put_change(:settled_at, DateTime.utc_now())
    |> put_change(:failure_kind, nil)
    |> put_change(:failure_message, nil)
  end

  def mark_failed_changeset(%__MODULE__{} = sweep, kind, message) do
    sweep
    |> change(
      status: "failed",
      failure_kind: to_string(kind),
      failure_message: truncate(message)
    )
  end

  def mark_skipped_changeset(%__MODULE__{} = sweep, reason) do
    sweep
    |> change(status: "skipped", failure_message: truncate(reason))
  end

  defp truncate(nil), do: nil
  defp truncate(msg), do: String.slice(to_string(msg), 0, 500)
end
