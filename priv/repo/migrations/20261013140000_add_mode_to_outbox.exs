defmodule Malipo.Repo.Migrations.AddModeToOutbox do
  use Ecto.Migration

  # KioskPay sandbox (test mode) K3 — the outbox carries the mode so the
  # dispatcher can skip the monolith for sandbox events while still delivering
  # the merchant webhook. Defaults to `live` for existing rows.
  def change do
    alter table(:outbox) do
      add(:mode, :string, null: false, default: "live", size: 8)
    end

    create(index(:outbox, [:mode, :status]))
  end
end
