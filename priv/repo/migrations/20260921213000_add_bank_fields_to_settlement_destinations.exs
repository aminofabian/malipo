defmodule Malipo.Repo.Migrations.AddBankFieldsToSettlementDestinations do
  use Ecto.Migration

  def change do
    alter table(:settlement_destinations) do
      add :bank_id, :string, size: 32
    end
  end
end
