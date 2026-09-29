# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :malipo,
  ecto_repos: [Malipo.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configure the endpoint
config :malipo, MalipoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MalipoWeb.ErrorHTML, json: MalipoWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Malipo.PubSub,
  live_view: [signing_salt: "hBFu/rJD"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  malipo: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  malipo: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Oban — STK poll / sweep / outbox dispatch queues
config :malipo, Oban,
  repo: Malipo.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       # Every minute until the Daraja adapter lands; tighten then.
       {"* * * * *", Malipo.Intents.Poller},
       {"* * * * *", Malipo.Intents.Sweeper}
     ]}
  ],
  queues: [
    stk_poll: 5,
    stk_sweep: 1,
    fee_sweep: 5,
    outbox: 5,
    webhooks: 10
  ]

# Platform Daraja — env bootstrap in runtime.exs; DB vault wins when populated
config :malipo, :daraja, []

# Cloak vault — ciphers configured in Malipo.Vault.init/1
config :malipo, Malipo.Vault, []

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
