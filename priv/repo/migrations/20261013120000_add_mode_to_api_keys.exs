defmodule Malipo.Repo.Migrations.AddModeToApiKeys do
  use Ecto.Migration

  # KioskPay sandbox (test mode) K1 — a key belongs to a mode.
  # `live` keys move real money; `test` keys are sandbox keys. A business can
  # hold one of each. Existing rows default to `live` (they are live keys).
  def change do
    alter table(:api_keys) do
      add(:mode, :string, null: false, default: "live", size: 8)
    end

    create(index(:api_keys, [:business_id, :mode]))
  end
end
