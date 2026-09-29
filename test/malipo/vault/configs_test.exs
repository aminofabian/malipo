defmodule Malipo.Vault.ConfigsTest do
  use Malipo.DataCase, async: true

  alias Malipo.Rails.Daraja.Platform
  alias Malipo.Vault.Configs

  setup do
    # Isolate Application env fallback between tests.
    previous = Application.get_env(:malipo, :daraja, [])
    Application.put_env(:malipo, :daraja, [])
    on_exit(fn -> Application.put_env(:malipo, :daraja, previous) end)
    :ok
  end

  test "update encrypts secrets and public_view never exposes them" do
    assert {:ok, row} =
             Configs.update(%{
               "enabled" => true,
               "environment" => "sandbox",
               "shortcode" => "4094529",
               "shortcode_type" => "paybill",
               "consumer_key" => "ck-live-value",
               "consumer_secret" => "cs-live-value",
               "passkey" => "pk-live-value",
               "callback_base" => "https://payments.kiosk.ke/"
             })

    view = Configs.public_view(row)

    assert view.has_consumer_key
    assert view.has_consumer_secret
    assert view.has_passkey
    assert view.shortcode == "4094529"
    assert view.callback_base == "https://payments.kiosk.ke"
    refute Map.has_key?(view, :consumer_key)
    refute Map.has_key?(view, :consumer_secret)
    refute Map.has_key?(view, :passkey)

    # Ciphertext in the DB is not plaintext.
    {:ok, uuid} = Ecto.UUID.dump(row.id)

    %{rows: [[key_bin, secret_bin, pass_bin]]} =
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        select consumer_key, consumer_secret, passkey
        from platform_daraja_settings
        where id = $1
        """,
        [uuid]
      )

    refute key_bin == "ck-live-value"
    refute secret_bin == "cs-live-value"
    refute pass_bin == "pk-live-value"
    assert is_binary(key_bin) and byte_size(key_bin) > 0
  end

  test "blank secret fields keep previously stored values" do
    assert {:ok, _} =
             Configs.update(%{
               "consumer_key" => "keep-me-key",
               "consumer_secret" => "keep-me-secret",
               "passkey" => "keep-me-pass",
               "shortcode" => "123456"
             })

    assert {:ok, row} =
             Configs.update(%{
               "consumer_key" => "",
               "consumer_secret" => "",
               "passkey" => "",
               "shortcode" => "654321"
             })

    assert row.shortcode == "654321"
    assert row.consumer_key == "keep-me-key"
    assert row.consumer_secret == "keep-me-secret"
    assert row.passkey == "keep-me-pass"
  end

  test "Platform.credentials prefers DB over env" do
    Application.put_env(:malipo, :daraja,
      consumer_key: "env-key",
      consumer_secret: "env-secret",
      shortcode: "111111",
      passkey: "env-pass"
    )

    assert {:ok, _} =
             Configs.update(%{
               "consumer_key" => "db-key",
               "consumer_secret" => "db-secret",
               "shortcode" => "4094529",
               "passkey" => "db-pass",
               "environment" => "production"
             })

    creds = Platform.credentials()
    assert creds["consumer_key"] == "db-key"
    assert creds["shortcode"] == "4094529"
    assert creds["environment"] == "production"
  end

  test "Platform.credentials falls back to env when DB incomplete" do
    Application.put_env(:malipo, :daraja,
      consumer_key: "env-key",
      consumer_secret: "env-secret",
      shortcode: "222222",
      passkey: "env-pass",
      environment: "sandbox"
    )

    # Empty row only
    _ = Configs.get!()

    creds = Platform.credentials()
    assert creds["consumer_key"] == "env-key"
    assert creds["shortcode"] == "222222"
  end

  test "Platform.credentials merges DB secrets with env shortcode" do
    Application.put_env(:malipo, :daraja,
      shortcode: "333333",
      environment: "sandbox"
    )

    assert {:ok, _} =
             Configs.update(%{
               "consumer_key" => "db-key",
               "consumer_secret" => "db-secret",
               "passkey" => "db-pass"
             })

    creds = Platform.credentials()
    assert creds["consumer_key"] == "db-key"
    assert creds["consumer_secret"] == "db-secret"
    assert creds["passkey"] == "db-pass"
    assert creds["shortcode"] == "333333"
    assert Platform.missing_fields() == []
  end
end
