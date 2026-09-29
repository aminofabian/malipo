defmodule Malipo.Vault.Settings do
  @moduledoc """
  Singleton platform Daraja credentials — encrypted in Postgres.

  UI is write-only: getters expose `has_*` flags and never ciphertext plaintext.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Malipo.Encrypted.Binary

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "platform_daraja_settings" do
    field :enabled, :boolean, default: false
    field :environment, :string, default: "sandbox"
    field :shortcode, :string
    field :shortcode_type, :string, default: "paybill"

    field :consumer_key, Binary
    field :consumer_secret, Binary
    field :passkey, Binary

    field :callback_base, :string

    field :last_tested_at, :utc_datetime_usec
    field :last_test_status, :string
    field :last_test_message, :string

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc """
  Changeset for admin forms — never seeds secret fields from the DB row.
  Placeholders stay empty; `Configs.update/1` keeps prior secrets when blank.
  """
  def form_changeset(%__MODULE__{} = row, attrs \\ %{}) do
    blank =
      row
      |> Map.put(:consumer_key, nil)
      |> Map.put(:consumer_secret, nil)
      |> Map.put(:passkey, nil)

    changeset(blank, attrs)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [
      :enabled,
      :environment,
      :shortcode,
      :shortcode_type,
      :consumer_key,
      :consumer_secret,
      :passkey,
      :callback_base,
      :last_tested_at,
      :last_test_status,
      :last_test_message
    ])
    |> update_change(:shortcode, &digits_or_nil/1)
    |> update_change(:callback_base, &trim_or_nil/1)
    |> update_change(:consumer_key, &trim_or_nil/1)
    |> update_change(:consumer_secret, &trim_or_nil/1)
    |> update_change(:passkey, &trim_or_nil/1)
    |> validate_inclusion(:environment, ["sandbox", "production"])
    |> validate_inclusion(:shortcode_type, ["paybill", "till"])
    |> validate_format(:shortcode, ~r/^\d{5,7}$/,
      message: "must be 5–7 digits",
      allow_nil: true
    )
    |> validate_callback_base()
  end

  defp validate_callback_base(changeset) do
    case get_change(changeset, :callback_base) || get_field(changeset, :callback_base) do
      nil ->
        changeset

      "" ->
        changeset

      url when is_binary(url) ->
        if String.starts_with?(url, "http://") or String.starts_with?(url, "https://") do
          changeset
        else
          add_error(changeset, :callback_base, "must start with http:// or https://")
        end
    end
  end

  defp digits_or_nil(nil), do: nil
  defp digits_or_nil(v) when is_binary(v) do
    d = Regex.replace(~r/\D/, v, "")
    if d == "", do: nil, else: d
  end

  defp trim_or_nil(nil), do: nil
  defp trim_or_nil(v) when is_binary(v) do
    t = String.trim(v)
    if t == "", do: nil, else: String.trim_trailing(t, "/")
  end
end
