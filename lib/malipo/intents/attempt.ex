defmodule Malipo.Intents.Attempt do
  @moduledoc """
  One rail call for an intent.

  Retries append rows instead of overwriting the intent — so support can answer
  "how many times did we prompt this customer?".
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Malipo.Intents.Intent

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @statuses ~w(sent pending_at_provider settled failed)

  schema "intent_attempts" do
    field :attempt_number, :integer
    field :checkout_request_id, :string
    field :merchant_request_id, :string
    field :status, :string, default: "sent"

    field :request_payload, :map, default: %{}
    field :response_payload, :map, default: %{}

    field :failure_kind, :string
    field :failure_message, :string
    field :failure_provider_code, :string

    belongs_to :intent, Intent

    timestamps()
  end

  @type t :: %__MODULE__{}

  def statuses, do: @statuses

  def create_changeset(intent_id, attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :attempt_number,
      :checkout_request_id,
      :merchant_request_id,
      :status,
      :request_payload,
      :response_payload,
      :failure_kind,
      :failure_message,
      :failure_provider_code
    ])
    |> put_change(:intent_id, intent_id)
    |> validate_required([:intent_id, :attempt_number, :status])
    |> validate_number(:attempt_number, greater_than: 0)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:intent_id, :attempt_number], name: :intent_attempts_number)
    |> foreign_key_constraint(:intent_id)
  end

  def update_changeset(%__MODULE__{} = attempt, attrs) do
    attempt
    |> cast(attrs, [
      :checkout_request_id,
      :merchant_request_id,
      :status,
      :response_payload,
      :failure_kind,
      :failure_message,
      :failure_provider_code
    ])
    |> validate_inclusion(:status, @statuses)
  end
end
