import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/malipo start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :malipo, MalipoWeb.Endpoint, server: true
end

config :malipo, MalipoWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Platform Daraja credentials (dark-mode / poller). DB vault wins when populated.
daraja =
  [
    consumer_key: System.get_env("DARAJA_CONSUMER_KEY"),
    consumer_secret: System.get_env("DARAJA_CONSUMER_SECRET"),
    shortcode: System.get_env("DARAJA_SHORTCODE"),
    passkey: System.get_env("DARAJA_PASSKEY"),
    environment: System.get_env("DARAJA_ENVIRONMENT") || "sandbox",
    shortcode_type: System.get_env("DARAJA_SHORTCODE_TYPE") || "paybill",
    party_b: System.get_env("DARAJA_PARTY_B"),
    base_url: System.get_env("DARAJA_BASE_URL"),
    callback_base: System.get_env("DARAJA_CALLBACK_BASE")
  ]
  |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)

config :malipo, :daraja, daraja

# Monolith settlement inbox (outbox dispatcher). Unset = dark-mode no-op deliver.
config :malipo, :monolith_payment_events_url, System.get_env("MONOLITH_PAYMENT_EVENTS_URL")

# Shared secret for /internal/* (Bearer). Unset = open (dev/test); required in prod edge.
config :malipo, :service_token, System.get_env("MALIPO_SERVICE_TOKEN")

# Super-admin console credentials (/admin/*). Unset in prod = console cannot be
# signed into (fail closed). Dev falls back to admin/admin for convenience.
if config_env() != :test do
  admin_user = System.get_env("MALIPO_ADMIN_USER")
  admin_password = System.get_env("MALIPO_ADMIN_PASSWORD")

  {admin_user, admin_password} =
    if config_env() == :dev and (is_nil(admin_user) or admin_user == "") do
      {"admin", "admin"}
    else
      {admin_user, admin_password}
    end

  config :malipo, :admin_auth, user: admin_user, password: admin_password

  cond do
    config_env() == :dev and admin_user == "admin" and admin_password == "admin" ->
      IO.puts(
        :stderr,
        "[malipo] /admin is using the default credentials admin/admin — " <>
          "set MALIPO_ADMIN_USER and MALIPO_ADMIN_PASSWORD to change them."
      )

    is_nil(admin_user) or admin_user == "" or is_nil(admin_password) or admin_password == "" ->
      IO.puts(
        :stderr,
        "[malipo] /admin has no credentials configured (MALIPO_ADMIN_USER / " <>
          "MALIPO_ADMIN_PASSWORD) — the super-admin console is disabled."
      )

    true ->
      :ok
  end
end

# CLOAK_KEY is required in prod (see Malipo.Vault). Optional elsewhere when
# :dev_fallback_key is configured.

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :malipo, MalipoWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
        # Gettext translations
        ~r"priv/gettext/.*\.po$",
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/malipo_web/router\.ex$",
        ~r"lib/malipo_web/(controllers|live|components)/.*\.(ex|heex)$"
      ]
    ]
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :malipo, Malipo.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :malipo, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :malipo, MalipoWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :malipo, MalipoWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :malipo, MalipoWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
