defmodule MalipoWeb.Plugs.AdminBasicAuth do
  @moduledoc """
  Optional HTTP basic auth for `/admin/*`.

  When `MALIPO_ADMIN_USER` and `MALIPO_ADMIN_PASSWORD` are set, credentials are
  required. When unset (local dark-mode), the plug is a no-op.
  """

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    user = System.get_env("MALIPO_ADMIN_USER")
    pass = System.get_env("MALIPO_ADMIN_PASSWORD")

    if present?(user) and present?(pass) do
      Plug.BasicAuth.basic_auth(conn, username: user, password: pass)
    else
      conn
    end
  end

  defp present?(v) when is_binary(v), do: String.trim(v) != ""
  defp present?(_), do: false
end
