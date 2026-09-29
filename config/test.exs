import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :malipo, Malipo.Repo,
  username: System.get_env("PGUSER") || System.get_env("USER") || "postgres",
  password: System.get_env("PGPASSWORD") || "",
  hostname: System.get_env("PGHOST") || "localhost",
  database: "malipo_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :malipo, MalipoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "t8AqK2l2ENVIEZ8d6LJZhg9xN3WFLtqa0hgV3R1uEQRiA6epvbnaAI57eJWvqgsp",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Oban does not run queues in test — assert with Oban.Testing helpers later.
config :malipo, Oban, testing: :manual

# Fixed Cloak key for deterministic encryption in tests.
config :malipo, Malipo.Vault,
  dev_fallback_key: Base.decode64!("dGVzdC1tYWxpcG8tY2xvYWsta2V5LTMyYnl0ZXMhISE=")

# Fast password hashes in test.
config :malipo, :connect_password_iterations, 1_000

# Deterministic super-admin credentials for tests (runtime.exs skips :test).
config :malipo, :admin_auth, user: "admin", password: "admin"
