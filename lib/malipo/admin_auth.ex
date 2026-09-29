defmodule Malipo.AdminAuth do
  @moduledoc """
  Super-admin console credentials.

  There are two sources of truth:

    * **DB operators** (`Malipo.AdminUsers`) — the normal path. Manage them on
      `/admin/team`.
    * **Env break-glass** (`MALIPO_ADMIN_USER` / `MALIPO_ADMIN_PASSWORD`) — always
      usable, which is also how the first DB operator is created.

  When neither exists the console **fails closed**: nobody can sign in. Env
  comparisons are constant-time; DB verification goes through
  `Malipo.AdminUsers.authenticate/2`.
  """

  alias Malipo.AdminUsers

  @doc "Whether anyone can sign in — an env credential or an active DB operator."
  @spec available?() :: boolean()
  def available? do
    env_configured?() or AdminUsers.any_active?()
  end

  @doc """
  Verify a submitted username/email + password against DB operators, then the
  env break-glass credentials. Returns `:ok` or `:error`.
  """
  @spec authenticate(term(), term()) :: :ok | :error
  def authenticate(user, password) when is_binary(user) and is_binary(password) do
    if db_authenticates?(user, password) or env_matches?(user, password) do
      :ok
    else
      :error
    end
  end

  def authenticate(_user, _password), do: :error

  defp db_authenticates?(user, password) do
    match?({:ok, _}, AdminUsers.authenticate(user, password))
  end

  defp env_configured? do
    {user, password} = env_credentials()
    present?(user) and present?(password)
  end

  defp env_matches?(user, password) do
    {expected_user, expected_password} = env_credentials()

    present?(expected_user) and present?(expected_password) and
      secure_eq(expected_user, user) and secure_eq(expected_password, password)
  end

  defp env_credentials do
    config = Application.get_env(:malipo, :admin_auth, [])

    {Keyword.get(config, :user), Keyword.get(config, :password)}
  end

  defp secure_eq(expected, given) when is_binary(expected) and is_binary(given) do
    Plug.Crypto.secure_compare(digest(expected), digest(given))
  end

  defp secure_eq(_expected, _given), do: false

  defp digest(value), do: :crypto.hash(:sha256, value)

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end
