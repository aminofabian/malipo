defmodule MalipoWeb.Admin.MerchantsLive do
  @moduledoc "Super-admin merchant destinations — read only."

  use MalipoWeb, :live_view

  alias Malipo.Merchants

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Merchants")
     |> assign(:rows, load())}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, assign(socket, :rows, load())}
  end

  defp load do
    for dest <- Merchants.list_destinations(50) do
      key = Merchants.get_active_key(dest.business_id)

      %{
        dest: dest,
        client_id: key && key.client_id,
        webhook_url: key && key.webhook_url,
        collections: Merchants.collections_allowed?(dest.business_id)
      }
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:merchants}>
      <div class="mb-6 flex items-end justify-between gap-4">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight">Merchants</h1>
          <p class="mt-1 text-sm text-base-content/60">
            Connect destinations and keys — secrets never shown here.
          </p>
        </div>
        <button type="button" class="btn btn-ghost btn-sm" phx-click="refresh">Refresh</button>
      </div>

      <div :if={@rows == []} class="py-16 text-center text-sm text-base-content/50">
        No merchants yet.
      </div>

      <div :if={@rows != []} class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr class="text-base-content/50">
              <th>Business</th>
              <th>Destination</th>
              <th>Status</th>
              <th>Client ID</th>
              <th>Webhook</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={r <- @rows} class="hover:bg-base-200/40">
              <td class="font-mono text-xs">{r.dest.business_id}</td>
              <td>
                <span class="font-medium">{dest_summary(r.dest)}</span>
                <span :if={r.dest.display_name} class="mt-0.5 block text-xs text-base-content/50">
                  {r.dest.display_name}
                </span>
              </td>
              <td>
                <span class={status_class(r.collections)}>
                  {if r.collections, do: "collecting", else: "inactive"}
                </span>
              </td>
              <td class="max-w-[10rem] truncate font-mono text-xs" title={r.client_id}>
                {r.client_id || "—"}
              </td>
              <td class="max-w-[12rem] truncate text-xs text-base-content/60" title={r.webhook_url}>
                {r.webhook_url || "—"}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.admin>
    """
  end

  defp dest_summary(%{kind: "till", till_number: n}), do: "Till #{n}"
  defp dest_summary(%{kind: "paybill", paybill_number: p, account_number: a}),
    do: "Paybill #{p} · #{a}"

  defp dest_summary(%{kind: "bank", paybill_number: p, account_number: a}),
    do: "Bank paybill #{p} · #{a}"

  defp dest_summary(%{kind: k}), do: k

  defp status_class(true), do: "font-medium text-success"
  defp status_class(false), do: "font-medium text-warning"
end
