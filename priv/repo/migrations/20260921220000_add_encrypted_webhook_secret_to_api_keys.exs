defmodule Malipo.Repo.Migrations.AddEncryptedWebhookSecretToApiKeys do
  use Ecto.Migration

  def change do
    alter table(:api_keys) do
      # Cloak-encrypted plaintext for HMAC signing. Hash remains write-only proof.
      add :webhook_secret, :binary
    end
  end
end
