defmodule MalipoWeb.Admin.TransactionsLive do
  @moduledoc """
  Super-admin unified money feed — STK intents and C2B till receipts in one
  stream. Route: `/admin/transactions`.
  """

  use MalipoWeb, :live_view

  alias Malipo.Admin

  @filters [
    {"all", "All"},
    {"stk", "STK intents"},
    {"c2b", "Till receipts"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Transactions")
     |> assign(:filters, @filters)
     |> assign(:filter, "all")
     |> load()}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket)
      when filter in ["all", "stk", "c2b"] do
    {:noreply, socket |> assign(:filter, filter) |> load()}
  end

  def handle_event("refresh", _params, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    assign(socket, :rows, Admin.list_transactions(100, socket.assigns.filter))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:transactions} admin={@current_admin}>
      <div class="mb-6 flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight">Transactions</h1>
          <p class="mt-1 text-sm text-base-content/60">
            Every STK intent and C2B till receipt, newest first.
          </p>
        </div>
        <div class="flex items-center gap-2">
          <div class="join">
            <button
              :for={{value, label} <- @filters}
              type="button"
              phx-click="filter"
              phx-value-filter={value}
              class={["btn btn-sm join-item", @filter == value && "btn-active"]}
            >
              {label}
            </button>
          </div>
          <button type="button" class="btn btn-ghost btn-sm" phx-click="refresh">Refresh</button>
        </div>
      </div>

      <div :if={@rows == []} class="py-16 text-center text-sm text-base-content/50">
        No transactions match this filter.
      </div>

      <div :if={@rows != []} class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr class="text-base-content/50">
              <th>When</th>
              <th>Type</th>
              <th>Status</th>
              <th class="text-right">Amount</th>
              <th>Reference</th>
              <th>Payer</th>
              <th>Business</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={tx <- @rows} id={tx.id} class="hover:bg-base-200/40">
              <td class="whitespace-nowrap text-xs text-base-content/50">{fmt(tx.at)}</td>
              <td>
                <span class={[
                  "badge badge-sm",
                  tx.kind == "stk" && "badge-info",
                  tx.kind == "c2b" && "badge-accent"
                ]}>
                  {String.upcase(tx.kind)}
                </span>
              </td>
              <td>
                <span class={"badge badge-sm #{status_class(tx.status)}"}>{tx.status}</span>
                <span :if={tx.failure_kind} class="mt-0.5 block text-xs text-base-content/50">
                  {tx.failure_kind}
                </span>
              </td>
              <td class="text-right tabular-nums whitespace-nowrap">
                {money(tx.amount, tx.currency)}
              </td>
              <td class="max-w-[12rem] truncate font-mono text-xs" title={tx.reference}>
                <%= if tx.intent_id do %>
                  <.link navigate={~p"/admin/intents/#{tx.intent_id}"} class="link link-hover">
                    {tx.reference || "—"}
                  </.link>
                <% else %>
                  {tx.reference || "—"}
                <% end %>
              </td>
              <td class="text-xs">
                <span class="font-mono">{mask(tx.payer_msisdn)}</span>
                <span :if={tx.payer_name} class="mt-0.5 block text-base-content/50">{tx.payer_name}</span>
              </td>
              <td class="max-w-[9rem] truncate font-mono text-xs" title={tx.business_id}>
                {tx.business_id}
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

  defp money(%Decimal{} = amount, currency) do
    "#{Decimal.to_string(Decimal.round(amount, 2), :normal)} #{currency}"
  end

  defp money(other, currency), do: "#{other} #{currency}"

  defp fmt(nil), do: "—"
  defp fmt(%DateTime{} = dt), do: Calendar.strftime(dt, "%m-%d %H:%M")

  defp status_class(status) when status in ["settled", "matched"], do: "badge-success"
  defp status_class(status) when status in ["failed", "unmatched"], do: "badge-error"
  defp status_class(status) when status in ["prompted", "pending"], do: "badge-warning"
  defp status_class("expired"), do: "badge-ghost"
  defp status_class(_status), do: "badge-ghost"
end
