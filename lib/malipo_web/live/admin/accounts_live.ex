defmodule MalipoWeb.Admin.AccountsLive do
  @moduledoc "Super-admin Connect accounts — who signed up and what they collect. Route: `/admin/accounts`."

  use MalipoWeb, :live_view

  alias Malipo.Admin

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Accounts")
     |> assign(:rows, Admin.list_accounts(100))}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, assign(socket, :rows, Admin.list_accounts(100))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:accounts} admin={@current_admin}>
      <div class="mb-6 flex items-end justify-between gap-4">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight">Accounts</h1>
          <p class="mt-1 text-sm text-base-content/60">
            Merchants who signed up to Malipo Connect — {@rows |> length()} shown.
          </p>
        </div>
        <button type="button" class="btn btn-ghost btn-sm" phx-click="refresh">Refresh</button>
      </div>

      <div :if={@rows == []} class="py-16 text-center text-sm text-base-content/50">
        No accounts have signed up yet.
      </div>

      <div :if={@rows != []} class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr class="text-base-content/50">
              <th>Account</th>
              <th>Destination</th>
              <th>Collections</th>
              <th>Client ID</th>
              <th class="text-right">Intents</th>
              <th class="text-right">Settled</th>
              <th>Joined</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @rows} class="hover:bg-base-200/40">
              <td>
                <span class="font-medium">{row.account.email}</span>
                <span :if={row.account.display_name} class="mt-0.5 block text-xs text-base-content/50">
                  {row.account.display_name}
                </span>
                <span class="mt-0.5 block font-mono text-xs text-base-content/40">
                  {row.account.business_id}
                </span>
              </td>
              <td>
                <span :if={row.destination} class="text-sm">{dest_summary(row.destination)}</span>
                <span :if={is_nil(row.destination)} class="text-xs text-base-content/40">
                  none saved
                </span>
              </td>
              <td>
                <span class={collections_class(row)}>
                  {collections_label(row)}
                </span>
              </td>
              <td class="max-w-[9rem] truncate font-mono text-xs" title={row.key && row.key.client_id}>
                {(row.key && row.key.client_id) || "—"}
              </td>
              <td class="text-right tabular-nums">{row.intent_count}</td>
              <td class="text-right tabular-nums whitespace-nowrap">
                {kes(row.settled_volume)}
                <span class="mt-0.5 block text-xs text-base-content/40">
                  {row.settled_count} settled
                </span>
              </td>
              <td class="whitespace-nowrap text-xs text-base-content/50">
                {fmt(row.account.inserted_at)}
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
    do: "Bank #{p} · #{a}"

  defp dest_summary(%{kind: kind}), do: kind

  defp collections_label(%{destination: %{active: true, verified: true}}), do: "collecting"
  defp collections_label(%{destination: %{verified: true}}), do: "verified"
  defp collections_label(%{destination: %{}}), do: "unverified"
  defp collections_label(_), do: "inactive"

  defp collections_class(%{destination: %{active: true, verified: true}}),
    do: "font-medium text-success"

  defp collections_class(%{destination: %{verified: true}}), do: "text-info"
  defp collections_class(_), do: "text-base-content/50"

  defp kes(%Decimal{} = amount),
    do: "KES " <> Decimal.to_string(Decimal.round(amount, 2), :normal)

  defp kes(other), do: to_string(other)

  defp fmt(nil), do: "—"
  defp fmt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")
end
