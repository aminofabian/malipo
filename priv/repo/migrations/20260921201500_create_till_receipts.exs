defmodule Malipo.Repo.Migrations.CreateTillReceipts do
  use Ecto.Migration

  def change do
    create table(:till_receipts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :rail, :string, null: false, default: "daraja", size: 32
      # Safaricom TransID — unique money-in receipt.
      add :trans_id, :string, null: false, size: 64
      add :shortcode, :string, size: 16
      # Resolved later from shortcode / BillRef; opaque until then.
      add :business_id, :string, size: 64

      add :amount, :numeric, null: false, precision: 14, scale: 2
      add :currency, :string, null: false, default: "KES", size: 3

      add :payer_msisdn, :string, size: 32
      add :payer_name, :string, size: 128
      add :bill_ref, :string, size: 128
      add :transaction_type, :string, size: 64
      add :trans_time, :string, size: 32

      # unmatched | matched | ignored
      add :status, :string, null: false, default: "unmatched", size: 24
      add :matched_intent_id, references(:intents, type: :binary_id, on_delete: :nilify_all)

      add :raw_payload, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:till_receipts, [:rail, :trans_id], name: :till_receipts_trans)
    create index(:till_receipts, [:status, :inserted_at], name: :till_receipts_status_inserted)
    create index(:till_receipts, [:business_id, :inserted_at],
      name: :till_receipts_business_inserted,
      where: "business_id IS NOT NULL"
    )
    create index(:till_receipts, [:bill_ref],
      name: :till_receipts_bill_ref,
      where: "bill_ref IS NOT NULL"
    )
  end
end
