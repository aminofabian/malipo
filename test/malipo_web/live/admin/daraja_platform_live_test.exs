defmodule MalipoWeb.Admin.DarajaPlatformLiveTest do
  use MalipoWeb.ConnCase, async: true

  alias Malipo.Vault.Configs

  test "renders write-only form without secret values", %{conn: conn} do
    conn = log_in_admin(conn)

    assert {:ok, _} =
             Configs.update(%{
               "consumer_key" => "super-secret-key",
               "consumer_secret" => "super-secret-secret",
               "passkey" => "super-secret-pass",
               "shortcode" => "4094529",
               "callback_base" => "https://payments.kiosk.ke"
             })

    {:ok, view, html} = live(conn, ~p"/admin/daraja/platform")

    assert html =~ "Platform Daraja"
    assert html =~ "write-only"
    assert html =~ "Set"
    assert html =~ "4094529"
    refute html =~ "super-secret-key"
    refute html =~ "super-secret-secret"
    refute html =~ "super-secret-pass"

    assert render_submit(
             form(view, "#platform-daraja-form",
               settings: %{
                 shortcode: "1234567",
                 consumer_key: "brand-new-key",
                 consumer_secret: "brand-new-secret",
                 passkey: "brand-new-pass",
                 environment: "sandbox",
                 shortcode_type: "paybill",
                 callback_base: "https://example.com",
                 enabled: "true"
               }
             )
           ) =~ "Platform Daraja settings saved"

    creds = Configs.credentials()
    assert creds["consumer_key"] == "brand-new-key"
    assert creds["shortcode"] == "1234567"

    # Re-open: stored secrets must not appear in the DOM.
    {:ok, _view, html} = live(conn, ~p"/admin/daraja/platform")
    assert html =~ "1234567"
    assert html =~ "Set"
    refute html =~ "brand-new-key"
    refute html =~ "brand-new-secret"
    refute html =~ "brand-new-pass"
    refute html =~ "super-secret-key"
  end
end
