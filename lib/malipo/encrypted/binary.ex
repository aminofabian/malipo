defmodule Malipo.Encrypted.Binary do
  @moduledoc false
  use Cloak.Ecto.Binary, vault: Malipo.Vault
end
