defmodule Malipo.ConnectAccounts.Password do
  @moduledoc false

  @algo "pbkdf2_sha256"
  @iterations 120_000
  @dk_len 32

  @doc "Hash a password for storage."
  @spec hash(String.t()) :: String.t()
  def hash(password) when is_binary(password) do
    iterations = iterations()
    salt = :crypto.strong_rand_bytes(16)
    digest = derive(password, salt, iterations)
    Enum.join([@algo, Integer.to_string(iterations), b64(salt), b64(digest)], "$")
  end

  @doc "Constant-time verify."
  @spec verify(String.t(), String.t()) :: boolean()
  def verify(password, stored) when is_binary(password) and is_binary(stored) do
    case String.split(stored, "$") do
      [@algo, iter_s, salt_b64, digest_b64] ->
        with {iterations, ""} <- Integer.parse(iter_s),
             {:ok, salt} <- Base.decode64(salt_b64),
             {:ok, expected} <- Base.decode64(digest_b64) do
          actual = derive(password, salt, iterations)
          Plug.Crypto.secure_compare(actual, expected)
        else
          _ -> false
        end

      _ ->
        false
    end
  end

  def verify(_, _), do: false

  @doc "Burn a verify cycle when no user exists (timing side-channel)."
  @spec no_user_verify() :: :ok
  def no_user_verify do
    _ = hash("malipo-timing-padding")
    :ok
  end

  defp derive(password, salt, iterations) do
    :crypto.pbkdf2_hmac(:sha256, password, salt, iterations, @dk_len)
  end

  defp iterations do
    Application.get_env(:malipo, :connect_password_iterations, @iterations)
  end

  defp b64(bin), do: Base.encode64(bin)
end
