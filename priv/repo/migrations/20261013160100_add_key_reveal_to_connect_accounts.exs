defmodule Malipo.Repo.Migrations.AddKeyRevealToConnectAccounts do
  use Ecto.Migration

  # Reveal-a-key bookkeeping: a small per-account rate limit / lockout, plus the
  # time of the last successful reveal (audit surface).
  def change do
    alter table(:connect_accounts) do
      add(:reveal_attempts, :integer, null: false, default: 0)
      add(:reveal_locked_until, :utc_datetime_usec)
      add(:last_key_reveal_at, :utc_datetime_usec)
    end
  end
end
