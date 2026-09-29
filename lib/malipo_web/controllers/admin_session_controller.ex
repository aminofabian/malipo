defmodule MalipoWeb.AdminSessionController do
  @moduledoc """
  Sign in / sign out for the super-admin console.

  The session is written here (not in a LiveView) because the cookie can only be
  set on an HTTP response. The `:admin` pipeline already fetches the session and
  protects against CSRF, so the login form posts with a `_csrf_token`.
  """

  use MalipoWeb, :controller

  alias Malipo.AdminAuth

  @doc "POST /admin/login"
  def create(conn, %{"admin" => %{"user" => user, "password" => password}}) do
    if AdminAuth.authenticate(user, password) == :ok do
      conn
      # Rotate the session id on privilege change to defeat fixation.
      |> configure_session(renew: true)
      |> put_session(:admin_user, String.trim(user))
      |> put_flash(:info, "Signed in")
      |> redirect(to: ~p"/admin")
    else
      conn
      |> put_flash(:error, "Invalid credentials")
      |> redirect(to: ~p"/admin/login")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Enter your credentials")
    |> redirect(to: ~p"/admin/login")
  end

  @doc "DELETE /admin/logout"
  def delete(conn, _params) do
    conn
    |> configure_session(renew: true)
    |> delete_session(:admin_user)
    |> put_flash(:info, "Signed out")
    |> redirect(to: ~p"/admin/login")
  end
end
