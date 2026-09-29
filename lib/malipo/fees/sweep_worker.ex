defmodule Malipo.Fees.SweepWorker do
  @moduledoc """
  Oban worker — advances one fee sweep toward the configured fee account.

  * `manual` mode parks the sweep at `awaiting` for an operator.
  * `auto` mode performs a rail transfer and waits for the result callback.

  Retryable rail failures bubble up so Oban retries with backoff; permanent
  failures mark the sweep `failed`.
  """

  use Oban.Worker, queue: :fee_sweep, max_attempts: 6

  alias Malipo.Fees
  alias Malipo.Fees.Sweep

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"sweep_id" => id}}) do
    case Fees.get_sweep(id) do
      nil -> :ok
      %Sweep{status: "pending"} = sweep -> Fees.process_sweep(sweep)
      %Sweep{} -> :ok
    end
  end

  def perform(%Oban.Job{}), do: :ok
end
