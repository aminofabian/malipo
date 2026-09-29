defmodule MalipoWeb.Admin.TillLive do
  @moduledoc "Super-admin C2B till receipts — read only."

  use MalipoWeb, :live_view

  alias Malipo.Till

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Till")
     |> assign(:filter, "all")
     |> load_rows()}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket)
      when filter in ["all", "unmatched"] do
    {:noreply, socket |> assign(:filter, filter) |> load_rows()}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, load_rows(socket)}
  end

  defp load_rows(socket) do
    rows =
      case socket.assigns.filter do
        "unmatched" -> Till.list_unmatched(50)
        _ -> Till.list_recent(50)
      end

    assign(socket, :rows, rows)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:till}>
      <div class="mb-6 flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight">Till receipts</h1>
          <p class="mt-1 text-sm text-base-content/60">
            C2B money-in — unmatched rows need a sale match.
          </p>
        </div>
        <div class="flex items-center gap-2">
          <div class="join">
            <button
              type="button"
              phx-click="filter"
              phx-value-filter="all"
              class={["btn btn-sm join-item", @filter == "all" && "btn-active"]}
            >
              All
            </button>
            <button
              type="button"
              phx-click="filter"
              phx-value-filter="unmatched"
              class={["btn btn-sm join-item", @filter == "unmatched" && "btn-active"]}
            >
              Unmatched
            </button>
          </div>
          <button type="button" class="btn btn-ghost btn-sm" phx-click="refresh">Refresh</button>
        </div>
      </div>

      <div :if={@rows == []} class="py-16 text-center text-sm text-base-content/50">
        No receipts yet.
      </div>

      <div :if={@rows != []} class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr class="text-base-content/50">
              <th>Status</th>
              <th>Amount</th>
              <th>TransID</th>
              <th>Bill ref</th>
              <th>Payer</th>
              <th>When</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={r <- @rows} class="hover:bg-base-200/40">
              <td>
                <span class={status_class(r.status)}>{r.status}</span>
              </td>
              <td class="tabular-nums whitespace-nowrap">
                {Decimal.to_string(r.amount)} {r.currency}
              </td>
              <td class="font-mono text-xs">{r.trans_id}</td>
              <td class="max-w-[10rem] truncate font-mono text-xs" title={r.bill_ref}>
                {r.bill_ref || "—"}
              </td>
              <td class="text-xs">
                <span class="font-mono">{mask(r.payer_msisdn)}</span>
                <span :if={r.payer_name} class="mt-0.5 block text-base-content/50">{r.payer_name}</span>
              </td>
              <td class="whitespace-nowrap text-xs text-base-content/50">{fmt(r.inserted_at)}</td>
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

  defp status_class("matched"), do: "font-medium text-success"
  defp status_class("unmatched"), do: "font-medium text-warning"
  defp status_class(_), do: "text-base-content/50"
end
