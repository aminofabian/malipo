defmodule Malipo.Fees.Config do
  @moduledoc """
  Singleton fee settings: notification rates and the account that receives fees.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @kinds ~w(none till paybill bank)
  @sweep_modes ~w(manual auto)

  schema "fee_settings" do
    field :enabled, :boolean, default: true

    # Notification rates in KES cents (80 = KES 0.80).
    field :sms_rate, :integer, default: 80
    field :whatsapp_rate, :integer, default: 60

    # How collected fees are moved to the fee account.
    field :sweep_mode, :string, default: "manual"

    field :fee_destination_kind, :string, default: "none"
    field :fee_destination_till, :string
    field :fee_destination_paybill, :string
    field :fee_destination_account, :string
    field :fee_destination_bank_id, :string
    field :fee_destination_name, :string

    timestamps()
  end

  @type t :: %__MODULE__{}

  def kinds, do: @kinds
  def sweep_modes, do: @sweep_modes

  def changeset(row \\ %__MODULE__{}, attrs) do
    row
    |> cast(attrs, [
      :enabled,
      :sms_rate,
      :whatsapp_rate,
      :sweep_mode,
      :fee_destination_kind,
      :fee_destination_till,
      :fee_destination_paybill,
      :fee_destination_account,
      :fee_destination_bank_id,
      :fee_destination_name
    ])
    |> validate_inclusion(:fee_destination_kind, @kinds)
    |> validate_inclusion(:sweep_mode, @sweep_modes)
    |> validate_destination()
  end

  defp validate_destination(changeset) do
    case get_field(changeset, :fee_destination_kind) do
      "till" ->
        validate_format(changeset, :fee_destination_till, ~r/^\d{5,7}$/,
          message: "must be 5–7 digits"
        )

      "paybill" ->
        changeset
        |> validate_format(:fee_destination_paybill, ~r/^\d{5,7}$/, message: "must be 5–7 digits")
        |> validate_length(:fee_destination_account, min: 1, max: 32)

      "bank" ->
        changeset
        |> validate_format(:fee_destination_paybill, ~r/^\d{5,7}$/, message: "must be 5–7 digits")
        |> validate_length(:fee_destination_account, min: 1, max: 32)

      _ ->
        changeset
    end
  end
end
