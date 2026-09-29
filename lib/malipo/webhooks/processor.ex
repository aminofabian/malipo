defmodule Malipo.Webhooks.Processor do
  @moduledoc "Oban worker — interprets a persisted webhook_events row."

  use Oban.Worker, queue: :webhooks, max_attempts: 10

  alias Malipo.Webhooks

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"webhook_event_id" => id}}) do
    case Webhooks.process(id) do
      {:ok, _} -> :ok
      {:error, :duplicate} -> :ok
      {:error, :not_found} -> :ok
      {:error, :ignored} -> :ok
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
end
