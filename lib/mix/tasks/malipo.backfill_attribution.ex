defmodule Mix.Tasks.Malipo.BackfillAttribution do
  @shortdoc "Best-effort backfill of intent destination attribution"

  @moduledoc """
  Stamps `context.settlement_destination_id` on intents created before attribution
  existed, so per-destination totals include historical payments.

      mix malipo.backfill_attribution

  See `Malipo.Admin.backfill_destination_attribution/0`. Safe to run more than
  once — it only touches intents that have no destination id yet.
  """

  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    %{intents: intents, businesses: businesses} = Malipo.Admin.backfill_destination_attribution()

    Mix.shell().info("Attributed #{intents} intent(s) across #{businesses} business(es).")
  end
end
