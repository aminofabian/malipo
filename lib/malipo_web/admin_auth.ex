defmodule MalipoWeb.AdminAuth do
  @moduledoc """
  `on_mount` hooks that gate the LiveView super-admin console.

  `:require_admin` halts unauthenticated sockets and redirects them to the login
  page; `:redirect_if_authenticated` keeps signed-in operators away from the login
  page. Credentials themselves are verified by `Malipo.AdminAuth` in
  `MalipoWeb.AdminSessionController.create/2`, which is where the session is
  written (a LiveView cannot mutate the session cookie).
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2]

  def on_mount(:require_admin, _params, session, socket) do
    case session["admin_user"] do
      user when is_binary(user) and user != "" ->
        {:cont, assign(socket, :current_admin, user)}

      _ ->
        {:halt, redirect(socket, to: "/admin/login")}
    end
  end

  def on_mount(:redirect_if_authenticated, _params, session, socket) do
    case session["admin_user"] do
      user when is_binary(user) and user != "" ->
        {:halt, redirect(socket, to: "/admin")}

      _ ->
        {:cont, socket}
    end
  end
end
