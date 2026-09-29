defmodule Malipo.Repo.Migrations.CreatePlatformDarajaSettings do
  use Ecto.Migration

  def change do
    create table(:platform_daraja_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :enabled, :boolean, null: false, default: false
      add :environment, :string, null: false, default: "sandbox", size: 16
      add :shortcode, :string, size: 16
      add :shortcode_type, :string, null: false, default: "paybill", size: 16

      # Encrypted at rest via Cloak (write-only to the UI).
      add :consumer_key, :binary
      add :consumer_secret, :binary
      add :passkey, :binary

      # Public callback origin, e.g. https://kiosk.ke — not a secret.
      add :callback_base, :string, size: 512

      add :last_tested_at, :utc_datetime_usec
      add :last_test_status, :string, size: 32
      add :last_test_message, :string, size: 512

      timestamps(type: :utc_datetime_usec)
    end
  end
end
