defmodule Malipo.Merchants.ApiKey do
  @moduledoc """
  Merchant API credentials.

  - `client_secret` — hashed only (never recoverable)
  - `webhook_secret` — Cloak-encrypted so we can HMAC outbound webhooks; shown once at provision
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "api_keys" do
    field :business_id, :string
    field :client_id, :string
    field :client_secret_hash, :binary
    field :webhook_secret_hash, :binary
    field :webhook_secret, Malipo.Encrypted.Binary
    field :webhook_url, :string
    field :revoked_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(row \\ %__MODULE__{}, attrs) do
    row
    |> cast(attrs, [
      :business_id,
      :client_id,
      :client_secret_hash,
      :webhook_secret_hash,
      :webhook_secret,
      :webhook_url,
      :revoked_at
    ])
    |> validate_required([:business_id, :client_id, :client_secret_hash, :webhook_secret_hash])
    |> unique_constraint(:client_id)
  end

  def active?(%__MODULE__{revoked_at: nil}), do: true
  def active?(%__MODULE__{}), do: false
end
