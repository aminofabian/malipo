defmodule Malipo.Repo.Migrations.CreateFees do
  use Ecto.Migration

  def change do
    create table(:fee_bands, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Whole KES bounds (inclusive) and the flat fee for the band.
      add :amount_from, :integer, null: false
      add :amount_to, :integer, null: false
      add :fee, :integer, null: false, default: 0
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create index(:fee_bands, [:amount_from])

    create table(:fee_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :enabled, :boolean, null: false, default: true
      add :sms_rate, :integer, null: false, default: 80
      add :whatsapp_rate, :integer, null: false, default: 60

      # Where collected service fees are received (the platform's own account).
      add :fee_destination_kind, :string, size: 16
      add :fee_destination_till, :string, size: 16
      add :fee_destination_paybill, :string, size: 16
      add :fee_destination_account, :string, size: 32
      add :fee_destination_bank_id, :string, size: 64
      add :fee_destination_name, :string, size: 128

      timestamps(type: :utc_datetime_usec)
    end

    alter table(:intents) do
      add :fee_amount, :decimal, precision: 14, scale: 2
      add :net_amount, :decimal, precision: 14, scale: 2
    end
  end
end
