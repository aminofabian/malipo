defmodule Malipo.Rails.Daraja.Platform do
  @moduledoc """
  Platform Daraja credentials — DB (super-admin) merged with env fallback.

  Super-admin saves into `platform_daraja_settings` (encrypted). Env vars remain
  a bootstrap path for local dark-mode / Coolify. Fields are merged field-by-field
  (DB wins) so a partial admin save plus `DARAJA_SHORTCODE` in env still works.
  """

  alias Malipo.Vault.Configs

  @required ~w(consumer_key consumer_secret shortcode passkey)

  @spec credentials() :: map() | nil
  def credentials do
    merged = Map.merge(env_partial(), db_partial())

    if Enum.all?(@required, &present?(Map.get(merged, &1))) do
      merged
    else
      nil
    end
  end

  @doc "Human-readable list of missing required credential fields."
  @spec missing_fields() :: [String.t()]
  def missing_fields do
    merged = Map.merge(env_partial(), db_partial())

    @required
    |> Enum.reject(&present?(Map.get(merged, &1)))
    |> Enum.map(&String.replace(&1, "_", " "))
  end

  @spec callback_base() :: String.t() | nil
  def callback_base do
    Configs.callback_base() ||
      env_get(:callback_base) ||
      System.get_env("DARAJA_CALLBACK_BASE")
  end

  defp db_partial do
    row = Configs.get!()

    %{
      "consumer_key" => row.consumer_key,
      "consumer_secret" => row.consumer_secret,
      "passkey" => row.passkey,
      "shortcode" => row.shortcode,
      "environment" => row.environment || "sandbox",
      "shortcode_type" => row.shortcode_type || "paybill",
      "callback_base" => row.callback_base
    }
    |> drop_blank()
  rescue
    _ -> %{}
  end

  defp env_partial do
    cfg = Application.get_env(:malipo, :daraja, []) |> Map.new()

    %{
      "consumer_key" => cfg[:consumer_key] || cfg["consumer_key"],
      "consumer_secret" => cfg[:consumer_secret] || cfg["consumer_secret"],
      "shortcode" => cfg[:shortcode] || cfg["shortcode"],
      "passkey" => cfg[:passkey] || cfg["passkey"],
      "environment" => cfg[:environment] || cfg["environment"] || "sandbox",
      "shortcode_type" => cfg[:shortcode_type] || cfg["shortcode_type"] || "paybill",
      "party_b" => cfg[:party_b] || cfg["party_b"],
      "base_url" => cfg[:base_url] || cfg["base_url"],
      "transaction_type" => cfg[:transaction_type] || cfg["transaction_type"],
      "initiator_name" => cfg[:initiator_name] || cfg["initiator_name"],
      "security_credential" => cfg[:security_credential] || cfg["security_credential"],
      "command_id" => cfg[:command_id] || cfg["command_id"],
      "callback_base" => cfg[:callback_base] || cfg["callback_base"]
    }
    |> drop_blank()
  end

  defp env_get(key) do
    cfg = Application.get_env(:malipo, :daraja, []) |> Map.new()
    cfg[key] || cfg[Atom.to_string(key)]
  end

  defp drop_blank(map) do
    map
    |> Enum.reject(fn {_k, v} -> blank?(v) end)
    |> Map.new()
  end

  defp present?(v), do: not blank?(v)
  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(v) when is_binary(v), do: String.trim(v) == ""
  defp blank?(_), do: false
end
