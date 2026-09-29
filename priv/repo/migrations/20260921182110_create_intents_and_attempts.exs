defmodule Malipo.Repo.Migrations.CreateIntentsAndAttempts do
  use Ecto.Migration

  def up do
    create table(:intents, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :business_id, :string, null: false, size: 64
      add :idempotency_key, :string, null: false, size: 191
      add :rail, :string, null: false, default: "daraja", size: 32

      add :amount, :numeric, null: false, precision: 14, scale: 2
      add :currency, :string, null: false, default: "KES", size: 3
      add :payer_msisdn, :string, null: false, size: 32

      # pending → prompted → settled | failed | expired
      add :status, :string, null: false, default: "pending", size: 24

      # Opaque to Malipo — echoed on settlement events.
      add :context, :map, null: false, default: %{}

      add :checkout_request_id, :string, size: 128
      add :merchant_request_id, :string, size: 128
      add :receipt, :string, size: 64

      add :failure_kind, :string, size: 64
      add :failure_message, :string, size: 512
      add :failure_provider_code, :string, size: 32

      add :expires_at, :utc_datetime_usec, null: false
      add :prompted_at, :utc_datetime_usec
      add :settled_at, :utc_datetime_usec
      add :failed_at, :utc_datetime_usec
      add :expired_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:intents, [:business_id, :idempotency_key], name: :intents_idem)
    create unique_index(:intents, [:rail, :receipt],
      name: :intents_receipt,
      where: "receipt IS NOT NULL"
    )
    create index(:intents, [:status, :expires_at], name: :intents_status_expires)
    create index(:intents, [:checkout_request_id],
      name: :intents_checkout,
      where: "checkout_request_id IS NOT NULL"
    )
    create index(:intents, [:business_id, :inserted_at], name: :intents_business_inserted)

    create table(:intent_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :intent_id, references(:intents, type: :binary_id, on_delete: :delete_all),
        null: false

      add :attempt_number, :integer, null: false
      add :checkout_request_id, :string, size: 128
      add :merchant_request_id, :string, size: 128

      # sent | pending_at_provider | settled | failed
      add :status, :string, null: false, default: "sent", size: 32

      add :request_payload, :map, null: false, default: %{}
      add :response_payload, :map, null: false, default: %{}

      add :failure_kind, :string, size: 64
      add :failure_message, :string, size: 512
      add :failure_provider_code, :string, size: 32

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:intent_attempts, [:intent_id, :attempt_number],
      name: :intent_attempts_number
    )
    create index(:intent_attempts, [:checkout_request_id],
      name: :intent_attempts_checkout,
      where: "checkout_request_id IS NOT NULL"
    )

    # Settled is immutable. Failed/expired may still move to settled on a late
    # provider success (Daraja defect §25.1.4). Any other resurrection is rejected.
    execute("""
    CREATE OR REPLACE FUNCTION intents_no_resurrect()
    RETURNS trigger AS $$
    BEGIN
      IF OLD.status = 'settled' AND NEW.status IS DISTINCT FROM OLD.status THEN
        RAISE EXCEPTION 'intent % is settled and cannot change status', OLD.id
          USING ERRCODE = 'check_violation';
      END IF;

      IF OLD.status IN ('failed', 'expired')
         AND NEW.status IS DISTINCT FROM OLD.status
         AND NEW.status <> 'settled' THEN
        RAISE EXCEPTION 'intent % is % and may only move to settled', OLD.id, OLD.status
          USING ERRCODE = 'check_violation';
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER intents_no_resurrect
    BEFORE UPDATE OF status ON intents
    FOR EACH ROW
    EXECUTE PROCEDURE intents_no_resurrect();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS intents_no_resurrect ON intents;")
    execute("DROP FUNCTION IF EXISTS intents_no_resurrect();")
    drop table(:intent_attempts)
    drop table(:intents)
  end
end
