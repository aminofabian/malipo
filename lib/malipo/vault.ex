defmodule Malipo.Vault do
  @moduledoc """
  Envelope encryption for Daraja credentials (Cloak).

  Boot fails closed in prod when `CLOAK_KEY` is missing (Daraja defect §25.1.5).
  Dev/test may set `:dev_fallback_key` in config — never use that in production.
  """

  use Cloak.Vault, otp_app: :malipo

  @impl GenServer
  def init(config) do
    config =
      Keyword.put(config, :ciphers,
        default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: cloak_key!(config), iv_length: 12}
      )

    {:ok, config}
  end

  defp cloak_key!(config) do
    case System.get_env("CLOAK_KEY") do
      key when is_binary(key) and key != "" ->
        Base.decode64!(key)

      _ ->
        case Keyword.get(config, :dev_fallback_key) do
          key when is_binary(key) and byte_size(key) == 32 ->
            key

          _ ->
            raise """
            CLOAK_KEY is required (base64-encoded 32-byte AES key).
            Generate with: openssl rand -base64 32
            """
        end
    end
  end
end
