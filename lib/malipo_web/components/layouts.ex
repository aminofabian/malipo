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

  attr :admin, :string, default: nil, doc: "the signed-in operator, shown in the header"
  slot :inner_block, required: true

  def admin(assigns) do
    ~H"""
    <div class="min-h-dvh bg-base-100 text-base-content">
      <header class="border-b border-base-300">
        <div class="mx-auto flex max-w-6xl items-center justify-between gap-4 px-4 py-4 sm:px-6">
          <div class="flex items-baseline gap-3">
            <a href={~p"/admin"} class="text-lg font-semibold tracking-tight">
              Malipo
            </a>
            <span class="text-xs text-base-content/50">super admin</span>
          </div>
          <div class="flex items-center gap-3">
            <span :if={@admin} class="hidden text-xs text-base-content/50 sm:inline">
              {gettext("Signed in as")} <span class="font-medium text-base-content">{@admin}</span>
            </span>
            <.theme_toggle />
            <form action={~p"/admin/logout"} method="post" class="inline">
              <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
              <input type="hidden" name="_method" value="delete" />
              <button type="submit" class="btn btn-ghost btn-sm">{gettext("Sign out")}</button>
            </form>
          </div>
        </div>
        <nav class="mx-auto flex max-w-6xl gap-1 overflow-x-auto px-4 pb-3 sm:px-6">
          <.admin_nav_link href={~p"/admin"} current={@current == :dashboard}>
            Overview
          </.admin_nav_link>
          <.admin_nav_link href={~p"/admin/transactions"} current={@current == :transactions}>
            Transactions
          </.admin_nav_link>
          <.admin_nav_link href={~p"/admin/intents"} current={@current == :intents}>
            Intents
          </.admin_nav_link>
          <.admin_nav_link href={~p"/admin/till"} current={@current == :till}>
            Till
          </.admin_nav_link>
          <.admin_nav_link href={~p"/admin/accounts"} current={@current == :accounts}>
            Accounts
          </.admin_nav_link>
          <.admin_nav_link href={~p"/admin/outbox"} current={@current == :outbox}>
            Outbox
          </.admin_nav_link>
          <.admin_nav_link href={~p"/admin/merchants"} current={@current == :merchants}>
            Merchants
          </.admin_nav_link>
          <.admin_nav_link href={~p"/admin/team"} current={@current == :team}>
            Team
          </.admin_nav_link>
          <.admin_nav_link href={~p"/admin/fees"} current={@current == :fees}>
            Fees
          </.admin_nav_link>
          <.admin_nav_link href={~p"/admin/daraja/platform"} current={@current == :daraja}>
            Daraja
          </.admin_nav_link>
        </nav>
      </header>

      <main class="mx-auto max-w-6xl px-4 py-8 sm:px-6">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  attr :href, :string, required: true
  attr :current, :boolean, default: false
  slot :inner_block, required: true

  defp admin_nav_link(assigns) do
    ~H"""
    <a
      href={@href}
      class={[
        "rounded-md px-3 py-1.5 text-sm whitespace-nowrap transition-colors",
        @current && "bg-base-200 font-medium text-base-content",
        !@current && "text-base-content/60 hover:bg-base-200/60 hover:text-base-content"
      ]}
    >
      {render_slot(@inner_block)}
    </a>
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
