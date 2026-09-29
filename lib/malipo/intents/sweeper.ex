defmodule Malipo.Intents.Sweeper do
  @moduledoc """
  Oban worker — expires open intents past `expires_at`.

  Expiry is a local UX state; a late provider receipt may still settle
  (see intents_no_resurrect trigger).
  """

  use Oban.Worker, queue: :stk_sweep, max_attempts: 1

  alias Malipo.Intents

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Enum.each(Intents.list_expired_open(), fn intent ->
      _ = Intents.mark_expired(intent, %{failure_message: "Local expiry — awaiting late receipt"})
    end)

    :ok
  end
end
