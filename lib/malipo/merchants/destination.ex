defmodule Malipo.Merchants.Destination do
  @moduledoc """
  Where a merchant's collected M-Pesa should land.

  `bank` is the custody receive shape: Lipa Na M-Pesa bank paybill + account
  (same as Java `receive-mpesa-flow`), not a wire/SWIFT transfer.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @kinds ~w(till paybill bank)

  schema "settlement_destinations" do
    field :business_id, :string
    field :kind, :string
    field :till_number, :string
    field :paybill_number, :string
    field :account_number, :string
    field :bank_id, :string
    field :display_name, :string
    field :verified, :boolean, default: false
    field :activated, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(row \\ %__MODULE__{}, attrs) do
    row
    |> cast(attrs, [
      :business_id,
      :kind,
      :till_number,
      :paybill_number,
      :account_number,
      :bank_id,
      :display_name,
      :verified,
      :activated
    ])
    |> validate_required([:business_id, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> validate_kind_fields()
    |> unique_constraint(:business_id)
  end

  defp validate_kind_fields(cs) do
    case get_field(cs, :kind) do
      "till" ->
        cs
        |> validate_required([:till_number])
        |> validate_format(:till_number, ~r/^\d{5,7}$/)
        |> put_change(:paybill_number, nil)
        |> put_change(:account_number, nil)
        |> put_change(:bank_id, nil)

      "paybill" ->
        cs
        |> validate_required([:paybill_number, :account_number])
        |> validate_format(:paybill_number, ~r/^\d{5,7}$/)
        |> validate_length(:account_number, min: 1, max: 32)
        |> put_change(:till_number, nil)
        |> put_change(:bank_id, nil)

      "bank" ->
        cs
        |> validate_required([:paybill_number, :account_number])
        |> validate_format(:paybill_number, ~r/^\d{5,7}$/)
        |> validate_length(:account_number, min: 1, max: 32)
        |> put_change(:till_number, nil)

      _ ->
        cs
    end
  end
end
