defmodule Malipo.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MalipoWeb.Telemetry,
      Malipo.Vault,
      Malipo.Repo,
      {DNSCluster, query: Application.get_env(:malipo, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Malipo.PubSub},
      {Finch, name: Malipo.Finch},
      Malipo.Rails.TokenCache,
      {Oban, Application.fetch_env!(:malipo, Oban)},
      MalipoWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Malipo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MalipoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
