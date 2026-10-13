defmodule Malipo.Sandbox.AutoSettle do
  @moduledoc """
  Oban worker — settles a sandbox intent a few seconds after its simulated prompt.

  The default outcome for a test payment whose number is not one of the reserved
  sandbox numbers: it just works, the way a developer expects.
  """

  use Oban.Worker, queue: :sandbox, max_attempts: 3

  alias Malipo.Intents
  alias Malipo.Intents.Intent

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"intent_id" => id}}) do
    case Intents.get(id) do
      %Intent{mode: "test", status: "prompted"} = intent ->
        _ = Malipo.Sandbox.settle(intent)
        :ok

      _ ->
        :ok
    end
  end
end
