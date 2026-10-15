defmodule MalipoWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use MalipoWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
          </li>
          <li>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
          </li>
          <li>
            <.theme_toggle />
          </li>
          <li>
            <a href="https://phoenix.hexdocs.pm/overview.html" class="btn btn-primary">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  attr :flash, :map, required: true

  attr :current, :atom,
    default: :dashboard,
    doc:
      ":dashboard | :transactions | :intents | :till | :accounts | :outbox | :merchants | :team | :daraja | :fees"

  attr :admin, :string, default: nil, doc: "the signed-in operator, shown in the sidebar"
  slot :inner_block, required: true

  def admin(assigns) do
    ~H"""
    <div class="admin-shell min-h-dvh lg:grid lg:grid-cols-[var(--admin-sidebar)_minmax(0,1fr)]">
      <aside class="flex flex-col border-b border-[var(--admin-line)] lg:sticky lg:top-0 lg:h-dvh lg:border-r lg:border-b-0">
        <div class="flex items-center justify-between gap-3 px-4 pt-5">
          <.link navigate={~p"/admin"} class="flex items-center gap-2.5">
            <span class="grid size-8 shrink-0 place-items-center rounded-lg bg-[var(--admin-green)] text-sm font-bold text-white">
              M
            </span>
            <span class="text-[15px] font-semibold tracking-tight">Malipo</span>
            <span class="rounded-full bg-[var(--admin-chip)] px-2 py-1 text-center text-[9px] font-semibold uppercase leading-tight tracking-wide text-[var(--admin-muted)]">
              Super<br />admin
            </span>
          </.link>
          <.sign_out class="lg:hidden" />
        </div>

        <p :if={@admin} class="truncate px-4 pt-3 text-[11px] text-[var(--admin-muted)] lg:hidden">
          {gettext("Signed in as")}
          <span class="font-medium text-[var(--admin-ink)]">{@admin}</span>
        </p>

        <nav class="flex-1 space-y-6 overflow-y-auto px-3 py-6">
          <.nav_section label="Overview">
            <.nav_link href={~p"/admin"} current={@current == :dashboard}>Overview</.nav_link>
          </.nav_section>
          <.nav_section label="Money">
            <.nav_link href={~p"/admin/transactions"} current={@current == :transactions}>
              Transactions
            </.nav_link>
            <.nav_link href={~p"/admin/intents"} current={@current == :intents}>
              Intents
            </.nav_link>
          </.nav_section>
          <.nav_section label="Till">
            <.nav_link href={~p"/admin/till"} current={@current == :till}>Receipts</.nav_link>
            <.nav_link href={~p"/admin/outbox"} current={@current == :outbox}>Outbox</.nav_link>
          </.nav_section>
          <.nav_section label="Directory">
            <.nav_link href={~p"/admin/accounts"} current={@current == :accounts}>
              Accounts
            </.nav_link>
            <.nav_link href={~p"/admin/merchants"} current={@current == :merchants}>
              Merchants
            </.nav_link>
          </.nav_section>
          <div>
            <.nav_link href={~p"/admin/team"} current={@current == :team}>Team</.nav_link>
          </div>
          <.nav_section label="Config">
            <.nav_link href={~p"/admin/fees"} current={@current == :fees}>Fees</.nav_link>
            <.nav_link href={~p"/admin/daraja/platform"} current={@current == :daraja}>
              Daraja
            </.nav_link>
          </.nav_section>
        </nav>

        <div class="mt-auto hidden border-t border-[var(--admin-line)] px-4 py-4 lg:block">
          <p :if={@admin} class="text-[11px] text-[var(--admin-muted)]">{gettext("Signed in as")}</p>
          <p :if={@admin} class="truncate text-xs font-medium">{@admin}</p>
          <.sign_out class="mt-3 w-full text-left" />
          <div class="mt-4 origin-left scale-90">
            <.theme_toggle />
          </div>
        </div>
      </aside>

      <main class="min-w-0 px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp nav_section(assigns) do
    ~H"""
    <div>
      <p class="mb-1 px-3 text-[10px] font-semibold uppercase tracking-[0.14em] text-[var(--admin-muted)]">
        {@label}
      </p>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :href, :string, required: true
  attr :current, :boolean, default: false
  slot :inner_block, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@href}
      aria-current={@current && "page"}
      class={[
        "block rounded-lg px-3 py-2 text-sm transition-colors",
        @current && "bg-[var(--admin-mint)] font-medium text-[var(--admin-green-deep)]",
        !@current && "text-[var(--admin-ink)] hover:bg-[var(--admin-hover)]"
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :class, :string, default: nil

  defp sign_out(assigns) do
    ~H"""
    <form action={~p"/admin/logout"} method="post" class="inline">
      <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
      <input type="hidden" name="_method" value="delete" />
      <button
        type="submit"
        class={[
          "rounded-lg border border-[var(--admin-line)] bg-[var(--admin-card)] px-3 py-1.5 text-sm text-[var(--admin-ink)] hover:bg-[var(--admin-hover)]",
          @class
        ]}
      >
        {gettext("Sign out")}
      </button>
    </form>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
