defmodule Malipo.Repo.Migrations.CreateWebhookEventsAndOutbox do
  use Ecto.Migration

  def change do
    create table(:webhook_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # stk | c2b_validation | c2b_confirmation | b2b_result | b2b_timeout
      add :kind, :string, null: false, size: 32
      add :rail, :string, null: false, default: "daraja", size: 32

      # CheckoutRequestID (STK) or TransID (C2B) — unique for dedupe.
      add :dedupe_key, :string, size: 191

      add :raw_body, :text, null: false
      add :headers, :map, null: false, default: %{}
      add :payload, :map, null: false, default: %{}

      # received | processed | ignored | failed
      add :status, :string, null: false, default: "received", size: 24
      add :error_message, :string, size: 512

      add :intent_id, references(:intents, type: :binary_id, on_delete: :nilify_all)
      add :processed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:webhook_events, [:rail, :kind, :dedupe_key],
      name: :webhook_events_dedupe,
      where: "dedupe_key IS NOT NULL"
    )
    create index(:webhook_events, [:status, :inserted_at], name: :webhook_events_status_inserted)
    create index(:webhook_events, [:intent_id],
      name: :webhook_events_intent,
      where: "intent_id IS NOT NULL"
    )

    create table(:outbox, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Public event id the monolith dedupes on (evt_…).
      add :event_id, :string, null: false, size: 64
      add :event, :string, null: false, size: 64
      add :version, :integer, null: false, default: 1

      add :business_id, :string, null: false, size: 64
      add :intent_id, references(:intents, type: :binary_id, on_delete: :nilify_all)
      add :payload, :map, null: false, default: %{}

      # pending | delivered | failed
      add :status, :string, null: false, default: "pending", size: 24
      add :attempts, :integer, null: false, default: 0
      add :last_error, :string, size: 512
      add :delivered_at, :utc_datetime_usec
      add :next_attempt_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:outbox, [:event_id], name: :outbox_event_id)
    create index(:outbox, [:status, :next_attempt_at], name: :outbox_status_next)
    create index(:outbox, [:intent_id], name: :outbox_intent, where: "intent_id IS NOT NULL")
  end
end
