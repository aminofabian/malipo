defmodule Malipo.Rails.Daraja.Platform do
  @moduledoc """
  Platform Daraja credentials — DB (super-admin) first, then env fallback.

  Super-admin saves into `platform_daraja_settings` (encrypted). Env vars remain
  a bootstrap path for local dark-mode without opening the UI.
  """

  alias Malipo.Vault.Configs

  @spec credentials() :: map() | nil
  def credentials do
    case safe_db_credentials() do
      %{} = creds -> creds
      nil -> env_credentials()
    end
  end

  @spec callback_base() :: String.t() | nil
  def callback_base do
    Configs.callback_base() ||
      env_get(:callback_base) ||
      System.get_env("DARAJA_CALLBACK_BASE")
  end

  defp safe_db_credentials do
    Configs.credentials()
  rescue
    _ -> nil
  end

  defp env_credentials do
    cfg = Application.get_env(:malipo, :daraja, []) |> Map.new()

    key = cfg[:consumer_key] || cfg["consumer_key"]
    secret = cfg[:consumer_secret] || cfg["consumer_secret"]
    shortcode = cfg[:shortcode] || cfg["shortcode"]
    passkey = cfg[:passkey] || cfg["passkey"]

    if blank?(key) or blank?(secret) or blank?(shortcode) or blank?(passkey) do
      nil
    else
      %{
        "consumer_key" => key,
        "consumer_secret" => secret,
        "shortcode" => shortcode,
        "passkey" => passkey,
        "environment" => cfg[:environment] || cfg["environment"] || "sandbox",
        "shortcode_type" => cfg[:shortcode_type] || cfg["shortcode_type"] || "paybill",
        "party_b" => cfg[:party_b] || cfg["party_b"],
        "base_url" => cfg[:base_url] || cfg["base_url"],
        "transaction_type" => cfg[:transaction_type] || cfg["transaction_type"],
        "initiator_name" => cfg[:initiator_name] || cfg["initiator_name"],
        "security_credential" => cfg[:security_credential] || cfg["security_credential"],
        "command_id" => cfg[:command_id] || cfg["command_id"]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Map.new()
    end
  end

  defp env_get(key) do
    cfg = Application.get_env(:malipo, :daraja, []) |> Map.new()
    cfg[key] || cfg[Atom.to_string(key)]
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false
end
