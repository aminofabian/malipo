defmodule Malipo.Repo.Migrations.CreateConnectAccounts do
  use Ecto.Migration

  def change do
    create table(:connect_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :email, :string, null: false, size: 191
      add :password_hash, :string, null: false, size: 191
      add :business_id, :string, null: false, size: 64
      add :display_name, :string, size: 191

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:connect_accounts, [:email])
    create unique_index(:connect_accounts, [:business_id])
  end
end
