defmodule Malipo.Intents.Poller do
  @moduledoc """
  Oban worker — polls prompted intents against Daraja and settles or fails them.

  Replaces the monolith `GatewayStkPushPoller`. Credentials come from the platform
  Daraja config until the vault resolves per-tenant BYO.
  """

  use Oban.Worker, queue: :stk_poll, max_attempts: 3

  require Logger

  alias Malipo.Intents
  alias Malipo.Rails.Daraja.Platform

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Platform.credentials() do
      nil ->
        Logger.debug("STK poller skipped — platform Daraja credentials not configured")
        :ok

      creds ->
        Intents.list_prompted_for_poll(50)
        |> Enum.each(fn intent ->
          case Intents.reconcile_prompted(intent, creds) do
            {:ok, updated} ->
              Logger.info("STK poll reconciled intent=#{updated.id} status=#{updated.status}")

            {:pending, _} ->
              :ok

            {:error, reason} ->
              Logger.warning(
                "STK poll failed intent=#{intent.id} reason=#{inspect(reason)}"
              )
          end
        end)

        :ok
    end
  end
end
