defmodule Malipo.Outbox.Event do
  @moduledoc """
  Durable settlement event for the monolith (`POST /internal/v1/payment-events`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Malipo.Intents.Intent

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @events ~w(intent.settled intent.failed intent.expired till_receipt.unmatched rail.credentials_rejected)
  @statuses ~w(pending delivered failed)

  schema "outbox" do
    field :event_id, :string
    field :event, :string
    field :version, :integer, default: 1
    field :business_id, :string
    field :payload, :map, default: %{}
    field :status, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :last_error, :string
    field :delivered_at, :utc_datetime_usec
    field :next_attempt_at, :utc_datetime_usec

    belongs_to :intent, Intent

    timestamps()
  end

  @type t :: %__MODULE__{}

  def events, do: @events
  def statuses, do: @statuses

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :event_id,
      :event,
      :version,
      :business_id,
      :intent_id,
      :payload,
      :next_attempt_at
    ])
    |> validate_required([:event_id, :event, :business_id, :payload])
    |> validate_inclusion(:event, @events)
    |> put_change(:status, "pending")
    |> put_change(:attempts, 0)
    |> unique_constraint(:event_id, name: :outbox_event_id)
  end

  def mark_delivered_changeset(%__MODULE__{} = row) do
    row
    |> change()
    |> put_change(:status, "delivered")
    |> put_change(:delivered_at, DateTime.utc_now())
    |> put_change(:last_error, nil)
  end

  def mark_attempt_changeset(%__MODULE__{} = row, error, next_at)
      when is_binary(error) do
    row
    |> change()
    |> put_change(:attempts, row.attempts + 1)
    |> put_change(:last_error, String.slice(error, 0, 512))
    |> put_change(:next_attempt_at, next_at)
    |> put_change(:status, if(row.attempts + 1 >= 40, do: "failed", else: "pending"))
  end
end
