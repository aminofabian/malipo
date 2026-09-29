defmodule Malipo.Repo.Migrations.CreateFeeSweeps do
  use Ecto.Migration

  def change do
    alter table(:fee_settings) do
      # "manual" (record + operator action) or "auto" (B2B transfer).
      add :sweep_mode, :string, null: false, default: "manual"
    end

    # Money movement for collected service fees — one sweep per settled intent.
    create table(:fee_sweeps, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :intent_id, references(:intents, type: :binary_id, on_delete: :nothing)
      add :business_id, :string

      add :amount, :decimal, precision: 14, scale: 2, null: false
      add :currency, :string, null: false, default: "KES"

      add :status, :string, null: false, default: "pending"
      add :mode, :string, null: false, default: "manual"

      # Snapshot of the destination at sweep time (config may change later).
      add :destination_kind, :string
      add :destination_till, :string
      add :destination_paybill, :string
      add :destination_account, :string
      add :destination_name, :string

      add :provider_conversation_id, :string
      add :originator_conversation_id, :string
      add :receipt, :string
      add :failure_kind, :string
      add :failure_message, :string

      add :attempts, :integer, null: false, default: 0
      add :next_attempt_at, :utc_datetime_usec
      add :sent_at, :utc_datetime_usec
      add :settled_at, :utc_datetime_usec

      timestamps()
    end

    create index(:fee_sweeps, [:status])
    create unique_index(:fee_sweeps, [:intent_id])
    create index(:fee_sweeps, [:provider_conversation_id])
  end
end
