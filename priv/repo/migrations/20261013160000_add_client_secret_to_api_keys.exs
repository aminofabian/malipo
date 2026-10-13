defmodule Malipo.Repo.Migrations.AddClientSecretToApiKeys do
  use Ecto.Migration

  # Keep the client secret recoverable so the merchant can reveal it again after
  # re-entering their password. `client_secret_hash` stays for fast auth; this
  # column is Cloak-encrypted at rest. Existing rows are NULL until rotated.
  def change do
    alter table(:api_keys) do
      add(:client_secret, :binary)
    end
  end
end
