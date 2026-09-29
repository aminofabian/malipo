defmodule Malipo.ConnectAccounts.Password do
  @moduledoc false

  # Kept as a thin shim so existing call sites stay put; the implementation is
  # shared with admin users in `Malipo.Password`.
  defdelegate hash(password), to: Malipo.Password
  defdelegate verify(password, stored), to: Malipo.Password
  defdelegate no_user_verify(), to: Malipo.Password
end
