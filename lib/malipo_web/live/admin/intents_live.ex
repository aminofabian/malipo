defmodule MalipoWeb.Admin.IntentsLive do
  @moduledoc "Super-admin intent list — read only."

  use MalipoWeb, :live_view

  alias Malipo.Intents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Intents")
     |> assign(:intents, Intents.list_recent(50))}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, assign(socket, :intents, Intents.list_recent(50))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:intents} admin={@current_admin}>
      <div class="mb-6 flex items-end justify-between gap-4">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight">Intents</h1>
          <p class="mt-1 text-sm text-base-content/60">Recent STK intents — newest first.</p>
        </div>
        <button type="button" class="btn btn-ghost btn-sm" phx-click="refresh">Refresh</button>
      </div>

      <div :if={@intents == []} class="py-16 text-center text-sm text-base-content/50">
        No intents yet.
      </div>

      <div :if={@intents != []} class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr class="text-base-content/50">
              <th>Status</th>
              <th>Amount</th>
              <th>MSISDN</th>
              <th>Business</th>
              <th>Receipt / checkout</th>
              <th>When</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={i <- @intents} class="hover:bg-base-200/40">
              <td>
                <span class={status_class(i.status)}>{i.status}</span>
                <span :if={i.failure_kind} class="mt-0.5 block text-xs text-base-content/50">
                  {i.failure_kind}
                </span>
              </td>
              <td class="tabular-nums whitespace-nowrap">
                {Decimal.to_string(i.amount)} {i.currency}
              </td>
              <td class="font-mono text-xs">{mask(i.payer_msisdn)}</td>
              <td class="font-mono text-xs">{i.business_id}</td>
              <td
                class="max-w-[12rem] truncate font-mono text-xs"
                title={i.receipt || i.checkout_request_id}
              >
                {i.receipt || i.checkout_request_id || "—"}
              </td>
              <td class="whitespace-nowrap text-xs text-base-content/50">
                {fmt(i.inserted_at)}
              </td>
              <td class="text-right">
                <.link navigate={~p"/admin/intents/#{i.id}"} class="link link-hover text-xs">
                  View
                </.link>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.admin>
    """
  end

  defp mask(msisdn) when is_binary(msisdn) and byte_size(msisdn) >= 7 do
    String.slice(msisdn, 0, 4) <> "****" <> String.slice(msisdn, -3, 3)
  end

  defp mask(_), do: "—"

  defp fmt(nil), do: "—"
  defp fmt(%DateTime{} = dt), do: Calendar.strftime(dt, "%m-%d %H:%M")

  defp status_class("settled"), do: "font-medium text-success"
  defp status_class("failed"), do: "font-medium text-error"
  defp status_class("prompted"), do: "font-medium text-warning"
  defp status_class("expired"), do: "text-base-content/50"
  defp status_class(_), do: "font-medium"
end
