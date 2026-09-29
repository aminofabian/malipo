defmodule Malipo.Repo.Migrations.CreateMerchantsDestinationsAndApiKeys do
  use Ecto.Migration

  def change do
    create table(:settlement_destinations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :business_id, :string, null: false, size: 64
      add :kind, :string, null: false, size: 16
      add :till_number, :string, size: 16
      add :paybill_number, :string, size: 16
      add :account_number, :string, size: 64
      add :display_name, :string, size: 191

      # Format-checked until live till lookup / KES 1 lands.
      add :verified, :boolean, null: false, default: false
      # Collections only when activated (verified + confirmed).
      add :activated, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:settlement_destinations, [:business_id])

    create table(:api_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :business_id, :string, null: false, size: 64
      add :client_id, :string, null: false, size: 64
      add :client_secret_hash, :binary, null: false
      add :webhook_secret_hash, :binary, null: false
      add :webhook_url, :string, size: 512
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:api_keys, [:client_id])
    create index(:api_keys, [:business_id])
  end
end
