defmodule MalipoWeb.Admin.DarajaPlatformLive do
  @moduledoc """
  Super-admin platform Daraja credentials — write-only secrets.

  Route: `/admin/daraja/platform`
  """

  use MalipoWeb, :live_view

  alias Malipo.Rails.Daraja
  alias Malipo.Rails.Daraja.Platform
  alias Malipo.Rails.Failure
  alias Malipo.Vault.Configs
  alias Malipo.Vault.Settings

  @impl true
  def mount(_params, _session, socket) do
    row = Configs.get!()

    {:ok,
     socket
     |> assign(:page_title, "Platform Daraja")
     |> assign(:view, Configs.public_view(row))
     |> assign(:testing?, false)
     |> assign_form(Settings.form_changeset(row))}
  end

  @impl true
  def handle_event("validate", %{"settings" => params}, socket) do
    changeset =
      Configs.get!()
      |> Settings.form_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"settings" => params}, socket) do
    case Configs.update(params) do
      {:ok, row} ->
        {:noreply,
         socket
         |> put_flash(:info, "Platform Daraja settings saved")
         |> assign(:view, Configs.public_view(row))
         |> assign_form(Settings.form_changeset(row))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert))}
    end
  end

  def handle_event("test", _params, socket) do
    socket = assign(socket, :testing?, true)

    case Platform.credentials() do
      nil ->
        {:noreply,
         socket
         |> assign(:testing?, false)
         |> put_flash(:error, "Save consumer key, secret, shortcode, and passkey first")}

      creds ->
        {status, message} =
          case Daraja.validate(creds) do
            :ok ->
              {:verified, "OAuth + passkey probe succeeded"}

            {:error, %Failure{kind: :inconclusive, message: msg}} ->
              {:inconclusive, msg}

            {:error, %Failure{kind: kind, message: msg}}
            when kind in [:bad_passkey, :bad_credentials] ->
              {:failed, msg}

            {:error, %Failure{message: msg}} ->
              {:failed, msg}

            other ->
              {:failed, "Unexpected validate result: #{inspect(other)}"}
          end

        {:ok, row} = Configs.record_test(Configs.get!(), status, message)

        flash =
          case status do
            :verified -> {:info, "Connection verified — #{message}"}
            :inconclusive -> {:info, "Inconclusive — #{message}"}
            :failed -> {:error, "Test failed — #{message}"}
          end

        {kind, text} = flash

        {:noreply,
         socket
         |> assign(:testing?, false)
         |> assign(:view, Configs.public_view(row))
         |> put_flash(kind, text)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: :settings))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:daraja}>
      <div class="mx-auto max-w-2xl space-y-8">
        <header class="space-y-2">
          <h1 class="text-2xl font-semibold tracking-tight">Platform Daraja</h1>
          <p class="text-sm leading-relaxed text-base-content/60">
            Safaricom credentials for the shared platform shortcode. Secrets are write-only —
            this page never shows a stored key, secret, or passkey.
          </p>
        </header>

        <section class="space-y-3 border-t border-base-300 pt-6">
          <h2 class="text-sm font-semibold">Status</h2>
          <dl class="grid gap-3 text-sm sm:grid-cols-2">
            <div>
              <dt class="text-base-content/50">Consumer key</dt>
              <dd>{set_label(@view.has_consumer_key)}</dd>
            </div>
            <div>
              <dt class="text-base-content/50">Consumer secret</dt>
              <dd>{set_label(@view.has_consumer_secret)}</dd>
            </div>
            <div>
              <dt class="text-base-content/50">Passkey</dt>
              <dd>{set_label(@view.has_passkey)}</dd>
            </div>
            <div>
              <dt class="text-base-content/50">Last test</dt>
              <dd>
                <%= if @view.last_tested_at do %>
                  <span class={test_status_class(@view.last_test_status)}>
                    {@view.last_test_status || "unknown"}
                  </span>
                  <span class="text-base-content/50">
                    · {Calendar.strftime(@view.last_tested_at, "%Y-%m-%d %H:%M UTC")}
                  </span>
                <% else %>
                  <span class="text-base-content/50">Never</span>
                <% end %>
              </dd>
            </div>
          </dl>
          <p :if={@view.last_test_message} class="text-xs text-base-content/60">
            {@view.last_test_message}
          </p>
        </section>

        <.form
          for={@form}
          id="platform-daraja-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-5 border-t border-base-300 pt-6"
        >
          <.input
            field={@form[:enabled]}
            type="checkbox"
            label="Enable platform Daraja for dark-mode / poller"
          />

          <.input
            field={@form[:environment]}
            type="select"
            label="Environment"
            options={[Sandbox: "sandbox", Production: "production"]}
          />

          <.input
            field={@form[:shortcode_type]}
            type="select"
            label="Shortcode type"
            options={[Paybill: "paybill", Till: "till"]}
          />

          <.input
            field={@form[:shortcode]}
            type="text"
            label="Business shortcode"
            placeholder="4094529"
            autocomplete="off"
          />

          <.input
            field={@form[:callback_base]}
            type="url"
            label="Callback base URL"
            placeholder="https://payments.kiosk.ke"
            autocomplete="off"
          />

          <.input
            field={@form[:consumer_key]}
            type="password"
            label={"Consumer key" <> secret_hint(@view.has_consumer_key)}
            placeholder={if @view.has_consumer_key, do: "•••••••• (leave blank to keep)", else: ""}
            autocomplete="new-password"
          />

          <.input
            field={@form[:consumer_secret]}
            type="password"
            label={"Consumer secret" <> secret_hint(@view.has_consumer_secret)}
            placeholder={
              if @view.has_consumer_secret, do: "•••••••• (leave blank to keep)", else: ""
            }
            autocomplete="new-password"
          />

          <.input
            field={@form[:passkey]}
            type="password"
            label={"Lipa Na M-Pesa passkey" <> secret_hint(@view.has_passkey)}
            placeholder={if @view.has_passkey, do: "•••••••• (leave blank to keep)", else: ""}
            autocomplete="new-password"
          />

          <div class="flex flex-wrap gap-3 pt-2">
            <button type="submit" class="btn btn-primary" phx-disable-with="Saving…">
              Save settings
            </button>
            <button
              type="button"
              class="btn btn-ghost"
              phx-click="test"
              phx-disable-with="Testing…"
              disabled={@testing?}
            >
              Test connection
            </button>
          </div>
        </.form>
      </div>
    </Layouts.admin>
    """
  end

  defp set_label(true), do: "Set"
  defp set_label(false), do: "Not set"

  defp secret_hint(true), do: " (set — leave blank to keep)"
  defp secret_hint(false), do: ""

  defp test_status_class("verified"), do: "text-success font-medium"
  defp test_status_class("failed"), do: "text-error font-medium"
  defp test_status_class("inconclusive"), do: "text-warning font-medium"
  defp test_status_class(_), do: "font-medium"
end
