defmodule MalipoWeb.Admin.DashboardLive do
  @moduledoc "Super-admin overview — headline numbers and recent activity. Route: `/admin`."

  use MalipoWeb, :live_view

  alias Malipo.Admin
  alias Malipo.ConnectAccounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Overview")
     |> load()}
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    socket
    |> assign(:overview, Admin.overview())
    |> assign(:accounts, ConnectAccounts.list_recent(5))
    |> assign(:transactions, Admin.list_transactions(8))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:dashboard} admin={@current_admin}>
      <div class="mb-6 flex items-end justify-between gap-4">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight">Overview</h1>
          <p class="mt-1 text-sm text-base-content/60">
            Money movement across Malipo — accounts, intents, till receipts, outbox.
          </p>
        </div>
        <button type="button" class="btn btn-ghost btn-sm" phx-click="refresh">Refresh</button>
      </div>

      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <.stat
          label="Settled volume (24h)"
          value={kes(@overview.intents.settled_volume_24h)}
          sub={"#{kes(@overview.intents.settled_volume_7d)} in the last 7 days"}
        />
        <.stat
          label="Settled volume (all time)"
          value={kes(@overview.intents.settled_volume)}
          sub={"#{@overview.intents.settled} settled intents"}
        />
        <.stat
          label="Till receipts"
          value={to_string(@overview.till.total)}
          sub={"#{@overview.till.matched} matched · #{@overview.till.unmatched} unmatched"}
        />
        <.stat
          label="Connect accounts"
          value={to_string(@overview.accounts.total)}
          sub={"+#{@overview.accounts.new_7d} in the last 7 days"}
        />
        <.stat
          label="Intents (24h)"
          value={to_string(@overview.intents.last_24h)}
          sub={"#{@overview.intents.open} open · #{@overview.intents.failed} failed"}
        />
        <.stat
          label="Outbox"
          value={to_string(@overview.outbox.pending)}
          sub={"pending · #{@overview.outbox.failed} failed · #{@overview.outbox.delivered} delivered"}
        />
      </div>

      <div class="mt-10 grid gap-8 lg:grid-cols-2">
        <section class="space-y-3">
          <div class="flex items-center justify-between gap-4">
            <h2 class="text-sm font-semibold">Recent transactions</h2>
            <.link
              navigate={~p"/admin/transactions"}
              class="text-xs text-base-content/60 hover:text-base-content"
            >
              View all →
            </.link>
          </div>

          <p :if={@transactions == []} class="text-sm text-base-content/50">No transactions yet.</p>

          <div :if={@transactions != []} class="overflow-x-auto">
            <table class="table table-sm">
              <tbody>
                <tr :for={tx <- @transactions} class="hover:bg-base-200/40">
                  <td class="whitespace-nowrap text-xs text-base-content/50">{fmt(tx.at)}</td>
                  <td>
                    <.kind_badge kind={tx.kind} />
                  </td>
                  <td class="tabular-nums whitespace-nowrap">{money(tx.amount, tx.currency)}</td>
                  <td class="max-w-[10rem] truncate font-mono text-xs" title={tx.reference}>
                    {tx.reference || "—"}
                  </td>
                  <td><.status_badge status={tx.status} /></td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section class="space-y-3">
          <div class="flex items-center justify-between gap-4">
            <h2 class="text-sm font-semibold">Newest accounts</h2>
            <.link
              navigate={~p"/admin/accounts"}
              class="text-xs text-base-content/60 hover:text-base-content"
            >
              View all →
            </.link>
          </div>

          <p :if={@accounts == []} class="text-sm text-base-content/50">No accounts yet.</p>

          <ul :if={@accounts != []} class="divide-y divide-base-300">
            <li :for={account <- @accounts} class="flex items-center justify-between gap-4 py-2.5">
              <div class="min-w-0">
                <p class="truncate text-sm font-medium">{account.email}</p>
                <p class="truncate font-mono text-xs text-base-content/50">{account.business_id}</p>
              </div>
              <span class="whitespace-nowrap text-xs text-base-content/50">{fmt(account.inserted_at)}</span>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.admin>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :sub, :string, default: nil

  defp stat(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-300 bg-base-100 p-4">
      <p class="text-xs uppercase tracking-wide text-base-content/50">{@label}</p>
      <p class="mt-2 text-2xl font-semibold tabular-nums">{@value}</p>
      <p :if={@sub} class="mt-1 text-xs text-base-content/50">{@sub}</p>
    </div>
    """
  end

  attr :kind, :string, required: true

  defp kind_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm", @kind == "stk" && "badge-info", @kind == "c2b" && "badge-accent"]}>
      {String.upcase(@kind)}
    </span>
    """
  end

  attr :status, :string, required: true

  defp status_badge(assigns) do
    ~H"""
    <span class={"badge badge-sm #{status_class(@status)}"}>{@status}</span>
    """
  end

  defp status_class(status) when status in ["settled", "matched", "delivered"],
    do: "badge-success"

  defp status_class(status) when status in ["failed", "unmatched"], do: "badge-error"
  defp status_class(status) when status in ["prompted", "pending"], do: "badge-warning"
  defp status_class(_status), do: "badge-ghost"

  defp kes(%Decimal{} = amount),
    do: "KES " <> Decimal.to_string(Decimal.round(amount, 2), :normal)

  defp kes(other), do: to_string(other)

  defp money(%Decimal{} = amount, currency) do
    "#{Decimal.to_string(Decimal.round(amount, 2), :normal)} #{currency}"
  end

  defp money(other, currency), do: "#{other} #{currency}"

  defp fmt(nil), do: "—"
  defp fmt(%DateTime{} = dt), do: Calendar.strftime(dt, "%m-%d %H:%M")
  defp fmt(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%m-%d %H:%M")
end
