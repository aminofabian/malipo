defmodule Malipo.Webhooks.Event do
  @moduledoc """
  Raw Daraja webhook row — persisted before any interpretation.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Malipo.Intents.Intent

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @kinds ~w(stk c2b_validation c2b_confirmation b2b_result b2b_timeout)
  @statuses ~w(received processed ignored failed)

  schema "webhook_events" do
    field :kind, :string
    field :rail, :string, default: "daraja"
    field :dedupe_key, :string
    field :raw_body, :string
    field :headers, :map, default: %{}
    field :payload, :map, default: %{}
    field :status, :string, default: "received"
    field :error_message, :string
    field :processed_at, :utc_datetime_usec

    belongs_to :intent, Intent

    timestamps()
  end

  @type t :: %__MODULE__{}

  def kinds, do: @kinds
  def statuses, do: @statuses

  def ingest_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:kind, :rail, :dedupe_key, :raw_body, :headers, :payload])
    |> validate_required([:kind, :raw_body])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:rail, ["daraja"])
    |> put_change(:status, "received")
    |> unique_constraint([:rail, :kind, :dedupe_key], name: :webhook_events_dedupe)
  end

  def mark_processed_changeset(%__MODULE__{} = event, attrs) do
    event
    |> cast(attrs, [:intent_id, :error_message])
    |> put_change(:status, "processed")
    |> put_change(:processed_at, DateTime.utc_now())
    |> put_change(:error_message, nil)
  end

  def mark_ignored_changeset(%__MODULE__{} = event, reason) when is_binary(reason) do
    event
    |> change()
    |> put_change(:status, "ignored")
    |> put_change(:processed_at, DateTime.utc_now())
    |> put_change(:error_message, String.slice(reason, 0, 512))
  end

  def mark_failed_changeset(%__MODULE__{} = event, reason) when is_binary(reason) do
    event
    |> change()
    |> put_change(:status, "failed")
    |> put_change(:processed_at, DateTime.utc_now())
    |> put_change(:error_message, String.slice(reason, 0, 512))
  end
end
