defmodule Malipo.Fees.Band do
  @moduledoc """
  One row of the transaction fee schedule: an inclusive KES range and its flat fee.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "fee_bands" do
    field :amount_from, :integer
    field :amount_to, :integer
    field :fee, :integer, default: 0
    field :position, :integer, default: 0

    timestamps()
  end

  @type t :: %__MODULE__{}

  def changeset(row \\ %__MODULE__{}, attrs) do
    row
    |> cast(attrs, [:amount_from, :amount_to, :fee, :position])
    |> validate_required([:amount_from, :amount_to, :fee])
    |> validate_number(:amount_from, greater_than_or_equal_to: 0)
    |> validate_number(:amount_to, greater_than: 0)
    |> validate_number(:fee, greater_than_or_equal_to: 0)
    |> validate_range_order()
  end

  defp validate_range_order(changeset) do
    from = get_field(changeset, :amount_from)
    to = get_field(changeset, :amount_to)

    if is_integer(from) and is_integer(to) and to < from do
      add_error(changeset, :amount_to, "must be greater than or equal to the lower bound")
    else
      changeset
    end
  end
end
