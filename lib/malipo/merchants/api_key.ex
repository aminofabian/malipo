defmodule Malipo.Merchants.ApiKey do
  @moduledoc """
  Merchant API credentials.

  - `client_secret` — Cloak-encrypted so the merchant can reveal it again behind
    their password; `client_secret_hash` is kept for fast authentication.
  - `webhook_secret` — Cloak-encrypted so we can HMAC outbound webhooks (and reveal it).
  - `mode` — `"live"` (moves real money) or `"test"` (KioskPay sandbox). Stored, never inferred.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @modes ~w(live test)

  schema "api_keys" do
    field(:business_id, :string)
    field(:client_id, :string)
    field(:client_secret_hash, :binary)
    field(:client_secret, Malipo.Encrypted.Binary)
    field(:webhook_secret_hash, :binary)
    field(:webhook_secret, Malipo.Encrypted.Binary)
    field(:webhook_url, :string)
    field(:mode, :string, default: "live")
    field(:revoked_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(row \\ %__MODULE__{}, attrs) do
    row
    |> cast(attrs, [
      :business_id,
      :client_id,
      :client_secret_hash,
      :client_secret,
      :webhook_secret_hash,
      :webhook_secret,
      :webhook_url,
      :mode,
      :revoked_at
    ])
    |> validate_required([:business_id, :client_id, :client_secret_hash, :webhook_secret_hash])
    |> validate_inclusion(:mode, @modes)
    |> unique_constraint(:client_id)
  end

  def active?(%__MODULE__{revoked_at: nil}), do: true
  def active?(%__MODULE__{}), do: false

  def live?(%__MODULE__{mode: "live"}), do: true
  def live?(%__MODULE__{}), do: false

  def test?(%__MODULE__{mode: "test"}), do: true
  def test?(%__MODULE__{}), do: false
end
