defmodule MalipoWeb.Admin.LoginLive do
  @moduledoc """
  Super-admin sign-in page. Route: `/admin/login`.

  The form posts to `MalipoWeb.AdminSessionController` (plain HTTP) so the
  session cookie can be set; this LiveView only renders the page and shows the
  flash left behind by a failed attempt.
  """

  use MalipoWeb, :live_view

  import Phoenix.Controller, only: [get_csrf_token: 0]

  alias Malipo.AdminAuth

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Super admin sign in")
     |> assign(:available?, AdminAuth.available?())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grid min-h-dvh place-items-center bg-base-200 px-4 py-10">
      <div class="w-full max-w-sm">
        <div class="mb-6 text-center">
          <div class="text-lg font-semibold tracking-tight">Malipo</div>
          <p class="text-xs text-base-content/50">super admin console</p>
        </div>

        <div class="card border border-base-300 bg-base-100 shadow-sm">
          <div class="card-body gap-5">
            <div :if={!@available?} class="alert alert-warning text-sm">
              <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
              <span>
                No admin sign-in is configured. Set <code>MALIPO_ADMIN_USER</code>
                and <code>MALIPO_ADMIN_PASSWORD</code>
                on the service, then restart.
              </span>
            </div>

            <form action={~p"/admin/login"} method="post" id="admin-login-form" class="space-y-4">
              <input type="hidden" name="_csrf_token" value={get_csrf_token()} />

              <.input
                id="admin-user"
                name="admin[user]"
                type="text"
                label="Email or username"
                value=""
                autocomplete="username"
                autofocus
                required
              />

              <.input
                id="admin-password"
                name="admin[password]"
                type="password"
                label="Password"
                value=""
                autocomplete="current-password"
                required
              />

              <button type="submit" class="btn btn-primary w-full" disabled={!@available?}>
                Sign in
              </button>
            </form>
          </div>
        </div>

        <p class="mt-6 text-center text-xs text-base-content/40">
          Malipo operations — authorised personnel only.
        </p>
      </div>

      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end
end
