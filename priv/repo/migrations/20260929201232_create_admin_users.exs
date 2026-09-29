defmodule Malipo.Repo.Migrations.CreateAdminUsers do
  use Ecto.Migration

  def change do
    create table(:admin_users, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :email, :string, null: false, size: 191
      add :name, :string, size: 191
      add :password_hash, :string, null: false, size: 191
      add :role, :string, null: false, default: "admin", size: 24
      add :active, :boolean, null: false, default: true
      add :last_login_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:admin_users, [:email])
  end
end
