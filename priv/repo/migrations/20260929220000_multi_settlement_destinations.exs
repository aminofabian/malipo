defmodule Malipo.Repo.Migrations.MultiSettlementDestinations do
  use Ecto.Migration

  def change do
    drop unique_index(:settlement_destinations, [:business_id])

    alter table(:settlement_destinations) do
      add :active, :boolean, null: false, default: false
    end

    execute(
      "UPDATE settlement_destinations SET active = true WHERE verified = true AND activated = true",
      ""
    )

    execute(
      """
      UPDATE settlement_destinations d
      SET active = true
      WHERE NOT EXISTS (
        SELECT 1 FROM settlement_destinations x
        WHERE x.business_id = d.business_id AND x.active = true
      )
      AND d.id = (
        SELECT id FROM settlement_destinations y
        WHERE y.business_id = d.business_id
        ORDER BY y.inserted_at DESC
        LIMIT 1
      )
      """,
      ""
    )

    create unique_index(:settlement_destinations, [:business_id],
             where: "active = true",
             name: :settlement_destinations_one_active_per_business
           )

    create index(:settlement_destinations, [:business_id])
  end
end
