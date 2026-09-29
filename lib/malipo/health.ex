defmodule Malipo.Health do
  @moduledoc """
  Liveness / readiness checks for deploy probes.
  """

  alias Malipo.Repo
  alias Malipo.Rails.Daraja.Platform

  @doc "Process is up — no dependency checks."
  @spec live() :: :ok
  def live, do: :ok

  @doc """
  Ready to take traffic: Postgres responds and Cloak vault is running.

  Platform Daraja credentials are reported but do not fail readiness
  (dark-mode / shadow can run without them).
  """
  @spec ready() :: {:ok, map()} | {:error, map()}
  def ready do
    checks = %{
      database: database_check(),
      vault: vault_check(),
      daraja_credentials: credentials_check()
    }

    required_ok? =
      match?({:ok, _}, checks.database) and match?({:ok, _}, checks.vault)

    summary = %{
      status: if(required_ok?, do: "ready", else: "not_ready"),
      checks: Map.new(checks, fn {k, v} -> {k, format_check(v)} end)
    }

    if required_ok?, do: {:ok, summary}, else: {:error, summary}
  end

  defp database_check do
    case Repo.query("select 1", []) do
      {:ok, _} -> {:ok, "up"}
      {:error, err} -> {:error, Exception.message(err)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp vault_check do
    case Process.whereis(Malipo.Vault) do
      pid when is_pid(pid) -> {:ok, "up"}
      _ -> {:error, "Malipo.Vault not running"}
    end
  end

  defp credentials_check do
    case Platform.credentials() do
      %{} = creds when map_size(creds) > 0 ->
        {:ok, "configured (#{creds["environment"] || "unknown"})"}

      _ ->
        {:ok, "missing"}
    end
  end

  defp format_check({:ok, detail}), do: %{status: "ok", detail: detail}
  defp format_check({:error, detail}), do: %{status: "error", detail: detail}
end
