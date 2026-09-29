defmodule MalipoWeb.Admin.FeesLive do
  @moduledoc """
  Super-admin fee schedule, notification rates, and the account that receives
  service fees. Route: `/admin/fees`
  """

  use MalipoWeb, :live_view

  alias Malipo.Fees
  alias Malipo.Fees.Config

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Fees")
     |> assign(:bands, rows(Fees.list_bands()))
     |> assign(:sweeps, Fees.list_sweeps(25))
     |> assign_config_form(Fees.get_config!())}
  end

  @impl true
  def handle_event("validate_config", %{"config" => params}, socket) do
    changeset =
      Fees.get_config!()
      |> Config.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :config_form, to_form(changeset, as: :config))}
  end

  def handle_event("save_config", %{"config" => params}, socket) do
    case Fees.update_config(params) do
      {:ok, row} ->
        {:noreply,
         socket
         |> put_flash(:info, "Fee settings saved")
         |> assign_config_form(row)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, :config_form, to_form(Map.put(changeset, :action, :insert), as: :config))}
    end
  end

  def handle_event("add_band", _params, socket) do
    {:noreply, assign(socket, :bands, socket.assigns.bands ++ [blank_row()])}
  end

  def handle_event("delete_band", %{"key" => key}, socket) do
    {:noreply, assign(socket, :bands, Enum.reject(socket.assigns.bands, &(&1.key == key)))}
  end

  def handle_event("save_bands", %{"bands" => params}, socket) do
    list =
      params
      |> Map.values()
      |> Enum.sort_by(fn attrs -> to_int(attrs["amount_from"]) end)

    case Fees.replace_bands(list) do
      {:ok, bands} ->
        {:noreply,
         socket
         |> put_flash(:info, "Fee schedule saved")
         |> assign(:bands, rows(bands))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not save schedule — #{reason}")}
    end
  end

  def handle_event("sweep_settled", %{"id" => id}, socket) do
    case Fees.get_sweep(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Sweep not found")}

      sweep ->
        {:ok, _} = Fees.mark_sweep_settled(sweep)

        {:noreply,
         socket
         |> put_flash(:info, "Sweep marked settled")
         |> assign(:sweeps, Fees.list_sweeps(25))}
    end
  end

  def handle_event("sweep_skip", %{"id" => id}, socket) do
    case Fees.get_sweep(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Sweep not found")}

      sweep ->
        {:ok, _} = Fees.mark_sweep_skipped(sweep, "Skipped by operator")

        {:noreply,
         socket
         |> put_flash(:info, "Sweep skipped")
         |> assign(:sweeps, Fees.list_sweeps(25))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:fees} admin={@current_admin}>
      <div class="mx-auto max-w-3xl space-y-10">
        <header class="space-y-2">
          <h1 class="text-2xl font-semibold tracking-tight">Fees</h1>
          <p class="text-sm leading-relaxed text-base-content/60">
            Transaction fees are quoted per settlement. Adjust the bands, the SMS/WhatsApp
            rates, and where collected fees are received.
          </p>
        </header>

        <section class="space-y-4 border-t border-base-300 pt-6">
          <h2 class="text-sm font-semibold">Notification rates &amp; fee account</h2>

          <.form
            for={@config_form}
            id="fee-config-form"
            phx-change="validate_config"
            phx-submit="save_config"
            class="space-y-5"
          >
            <.input field={@config_form[:enabled]} type="checkbox" label="Apply transaction fees" />

            <div class="grid gap-4 sm:grid-cols-2">
              <.input
                field={@config_form[:sweep_mode]}
                type="select"
                label="Fee sweep mode"
                options={[Manual: "manual", "Automatic (via rail)": "auto"]}
              />
              <.input
                field={@config_form[:fee_destination_name]}
                type="text"
                label="Account label"
                placeholder="KioskPay fees"
              />
            </div>

            <p class="text-xs text-base-content/60">
              Manual records each fee as a sweep for you to action below. Automatic moves it
              through the rail using the rail's own credentials.
            </p>

            <div class="grid gap-4 sm:grid-cols-2">
              <.input
                field={@config_form[:sms_rate]}
                type="number"
                label="SMS rate (KES cents per message)"
              />
              <.input
                field={@config_form[:whatsapp_rate]}
                type="number"
                label="WhatsApp rate (KES cents per message)"
              />
            </div>

            <div class="grid gap-4 sm:grid-cols-2">
              <.input
                field={@config_form[:fee_destination_kind]}
                type="select"
                label="Fee account type"
                options={[None: "none", Till: "till", Paybill: "paybill", Bank: "bank"]}
              />
              <.input
                field={@config_form[:fee_destination_till]}
                type="text"
                label="Till number"
                placeholder="5738421"
              />
            </div>

            <div class="grid gap-4 sm:grid-cols-2">
              <.input
                field={@config_form[:fee_destination_paybill]}
                type="text"
                label="Paybill number"
                placeholder="123456"
              />
              <.input
                field={@config_form[:fee_destination_account]}
                type="text"
                label="Account number"
                placeholder="FEES"
              />
            </div>

            <div class="grid gap-4 sm:grid-cols-2">
              <.input
                field={@config_form[:fee_destination_bank_id]}
                type="text"
                label="Bank id (optional)"
              />
            </div>

            <p class="text-xs text-base-content/60">
              Fee amounts are whole KES. Counts for SMS/WhatsApp are stored in cents
              (80 = KES 0.80).
            </p>

            <button type="submit" class="btn btn-primary" phx-disable-with="Saving…">
              Save settings
            </button>
          </.form>
        </section>

        <section class="space-y-4 border-t border-base-300 pt-6">
          <div class="flex items-center justify-between gap-4">
            <h2 class="text-sm font-semibold">Transaction fee schedule</h2>
            <button type="button" class="btn btn-ghost btn-sm" phx-click="add_band">
              Add band
            </button>
          </div>

          <form id="fee-bands-form" phx-submit="save_bands" class="space-y-3">
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Amount from</th>
                    <th>Amount to</th>
                    <th>Fee (KES)</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={band <- @bands}>
                    <td>
                      <input
                        type="number"
                        name={"bands[#{band.key}][amount_from]"}
                        value={band.amount_from}
                        class="input input-sm input-bordered w-28"
                      />
                    </td>
                    <td>
                      <input
                        type="number"
                        name={"bands[#{band.key}][amount_to]"}
                        value={band.amount_to}
                        class="input input-sm input-bordered w-28"
                      />
                    </td>
                    <td>
                      <input
                        type="number"
                        name={"bands[#{band.key}][fee]"}
                        value={band.fee}
                        class="input input-sm input-bordered w-24"
                      />
                    </td>
                    <td>
                      <button
                        type="button"
                        class="btn btn-ghost btn-xs"
                        phx-click="delete_band"
                        phx-value-key={band.key}
                      >
                        Remove
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <button type="submit" class="btn btn-primary" phx-disable-with="Saving…">
              Save schedule
            </button>
          </form>
        </section>

        <section class="space-y-4 border-t border-base-300 pt-6">
          <div class="flex items-center justify-between gap-4">
            <h2 class="text-sm font-semibold">Recent fee sweeps</h2>
            <span class="text-xs text-base-content/60">
              {sweep_summary(@sweeps)}
            </span>
          </div>

          <p :if={@sweeps == []} class="text-sm text-base-content/60">
            No sweeps yet — they appear here as payments settle with a fee.
          </p>

          <div :if={@sweeps != []} class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Fee</th>
                  <th>Destination</th>
                  <th>Status</th>
                  <th>When</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={sweep <- @sweeps} id={"sweep-#{sweep.id}"}>
                  <td class="font-medium">{kes(sweep.amount)}</td>
                  <td class="text-xs">{sweep_destination(sweep)}</td>
                  <td>
                    <span class={"badge badge-sm #{status_class(sweep.status)}"}>
                      {sweep.status}
                    </span>
                  </td>
                  <td class="text-xs text-base-content/60">{short_time(sweep.inserted_at)}</td>
                  <td class="space-x-2 text-right">
                    <button
                      :if={sweep.status in ["awaiting", "sent"]}
                      type="button"
                      class="btn btn-ghost btn-xs"
                      phx-click="sweep_settled"
                      phx-value-id={sweep.id}
                    >
                      Mark settled
                    </button>
                    <button
                      :if={sweep.status in ["pending", "awaiting"]}
                      type="button"
                      class="btn btn-ghost btn-xs"
                      phx-click="sweep_skip"
                      phx-value-id={sweep.id}
                    >
                      Skip
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </Layouts.admin>
    """
  end

  defp assign_config_form(socket, %Config{} = row) do
    assign(socket, :config_form, to_form(Config.changeset(row, %{}), as: :config))
  end

  defp rows(bands) do
    Enum.map(bands, fn b ->
      %{key: b.id, amount_from: b.amount_from, amount_to: b.amount_to, fee: b.fee}
    end)
  end

  defp kes(%Decimal{} = amount) do
    "KES " <> (amount |> Decimal.round(2) |> Decimal.to_string(:normal))
  end

  defp kes(other), do: to_string(other)

  defp sweep_destination(%{destination_kind: "till", destination_till: till}), do: "Till #{till}"

  defp sweep_destination(%{
         destination_kind: kind,
         destination_paybill: paybill,
         destination_account: account
       })
       when kind in ["paybill", "bank"] do
    [paybill, account] |> Enum.reject(&is_nil/1) |> Enum.join(" · ")
  end

  defp sweep_destination(_), do: "—"

  defp status_class("settled"), do: "badge-success"
  defp status_class("failed"), do: "badge-error"
  defp status_class("awaiting"), do: "badge-warning"
  defp status_class("sent"), do: "badge-info"
  defp status_class(_), do: "badge-ghost"

  defp sweep_summary(sweeps) do
    open = Enum.count(sweeps, &(&1.status in ["pending", "awaiting", "sent"]))
    "#{open} open of #{length(sweeps)}"
  end

  defp short_time(nil), do: "—"

  defp short_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  defp blank_row, do: %{key: Ecto.UUID.generate(), amount_from: "", amount_to: "", fee: ""}

  defp to_int(nil), do: 0
  defp to_int(n) when is_integer(n), do: n

  defp to_int(s) do
    case Integer.parse(to_string(s)) do
      {n, _} -> n
      :error -> 0
    end
  end
end
