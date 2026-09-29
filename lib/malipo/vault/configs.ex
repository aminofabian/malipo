defmodule Malipo.Vault.Configs do
  @moduledoc """
  CRUD for the singleton platform Daraja settings row.

  Secrets are write-only: `public_view/1` never includes credential values.
  """

  import Ecto.Query

  alias Malipo.Repo
  alias Malipo.Vault.Settings

  @doc "Fetch the singleton row (creates an empty one if missing)."
  @spec get!() :: Settings.t()
  def get! do
    case Repo.one(from s in Settings, limit: 1) do
      %Settings{} = row ->
        row

      nil ->
        {:ok, row} =
          %Settings{}
          |> Settings.changeset(%{})
          |> Repo.insert()

        row
    end
  end

  @doc """
  Update settings. Blank secret fields keep the previously stored value
  (so the form can stay empty after save).
  """
  @spec update(map()) :: {:ok, Settings.t()} | {:error, Ecto.Changeset.t()}
  def update(attrs) when is_map(attrs) do
    row = get!()
    attrs = stringify(attrs) |> keep_blank_secrets(row)

    row
    |> Settings.changeset(attrs)
    |> Repo.update()
  end

  @doc "Record the outcome of `Daraja.validate/1`."
  @spec record_test(Settings.t(), :verified | :failed | :inconclusive, String.t()) ::
          {:ok, Settings.t()} | {:error, Ecto.Changeset.t()}
  def record_test(%Settings{} = row, status, message)
      when status in [:verified, :failed, :inconclusive] and is_binary(message) do
    row
    |> Settings.changeset(%{
      last_tested_at: DateTime.utc_now(),
      last_test_status: Atom.to_string(status),
      last_test_message: String.slice(message, 0, 500)
    })
    |> Repo.update()
  end

  @doc """
  Credentials map for `Malipo.Rails.Daraja` — or `nil` if incomplete.

  Prefer DB over env. Used by the poller and dark-mode pushes.
  """
  @spec credentials() :: map() | nil
  def credentials do
    row = get!()

    key = row.consumer_key
    secret = row.consumer_secret
    passkey = row.passkey
    shortcode = row.shortcode

    if present?(key) and present?(secret) and present?(passkey) and present?(shortcode) do
      %{
        "consumer_key" => key,
        "consumer_secret" => secret,
        "passkey" => passkey,
        "shortcode" => shortcode,
        "environment" => row.environment || "sandbox",
        "shortcode_type" => row.shortcode_type || "paybill",
        "callback_base" => row.callback_base
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Map.new()
    else
      nil
    end
  end

  @spec callback_base() :: String.t() | nil
  def callback_base do
    get!().callback_base
  end

  @doc "Safe map for templates / JSON — never includes secrets."
  @spec public_view(Settings.t()) :: map()
  def public_view(%Settings{} = row) do
    %{
      id: row.id,
      enabled: row.enabled,
      environment: row.environment,
      shortcode: row.shortcode,
      shortcode_type: row.shortcode_type,
      callback_base: row.callback_base,
      has_consumer_key: present?(row.consumer_key),
      has_consumer_secret: present?(row.consumer_secret),
      has_passkey: present?(row.passkey),
      last_tested_at: row.last_tested_at,
      last_test_status: row.last_test_status,
      last_test_message: row.last_test_message
    }
  end

  defp keep_blank_secrets(attrs, row) do
    attrs
    |> keep_if_blank("consumer_key", row.consumer_key)
    |> keep_if_blank("consumer_secret", row.consumer_secret)
    |> keep_if_blank("passkey", row.passkey)
  end

  defp keep_if_blank(attrs, key, existing) do
    case Map.get(attrs, key) do
      v when v in [nil, ""] -> Map.put(attrs, key, existing)
      _ -> attrs
    end
  end

  defp stringify(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} when is_binary(k) -> {k, v}
    end)
  end

  defp present?(v) when is_binary(v), do: String.trim(v) != ""
  defp present?(_), do: false
end
