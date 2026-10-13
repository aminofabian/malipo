defmodule Malipo.Repo.Migrations.AddModeToIntents do
  use Ecto.Migration

  # KioskPay sandbox (test mode) K2 — an intent records the mode it was created
  # under, so sandbox traffic is never mistaken for real money. Defaults to
  # `live` for existing rows.
  def change do
    alter table(:intents) do
      add(:mode, :string, null: false, default: "live", size: 8)
    end

    create(index(:intents, [:business_id, :mode, :inserted_at]))
  end
end
