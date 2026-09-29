defmodule MalipoWeb.Admin.OutboxLive do
  @moduledoc "Super-admin outbox — settlement events to the monolith."

  use MalipoWeb, :live_view

  alias Malipo.Outbox

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Outbox")
     |> assign(:rows, Outbox.list_recent(50))}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, assign(socket, :rows, Outbox.list_recent(50))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:outbox} admin={@current_admin}>
      <div class="mb-6 flex items-end justify-between gap-4">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight">Outbox</h1>
          <p class="mt-1 text-sm text-base-content/60">
            Events for the monolith — pending until delivered.
          </p>
        </div>
        <button type="button" class="btn btn-ghost btn-sm" phx-click="refresh">Refresh</button>
      </div>

      <div :if={@rows == []} class="py-16 text-center text-sm text-base-content/50">
        Outbox is empty.
      </div>

      <div :if={@rows != []} class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr class="text-base-content/50">
              <th>Status</th>
              <th>Event</th>
              <th>Business</th>
              <th>Attempts</th>
              <th>When</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={r <- @rows} class="hover:bg-base-200/40">
              <td>
                <span class={status_class(r.status)}>{r.status}</span>
                <span
                  :if={r.last_error}
                  class="mt-0.5 block max-w-[14rem] truncate text-xs text-error/80"
                  title={r.last_error}
                >
                  {r.last_error}
                </span>
              </td>
              <td>
                <span class="font-medium">{r.event}</span>
                <span class="mt-0.5 block font-mono text-xs text-base-content/50">{r.event_id}</span>
              </td>
              <td class="font-mono text-xs">{r.business_id}</td>
              <td class="tabular-nums">{r.attempts}</td>
              <td class="whitespace-nowrap text-xs text-base-content/50">{fmt(r.inserted_at)}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.admin>
    """
  end

  defp fmt(nil), do: "—"
  defp fmt(%DateTime{} = dt), do: Calendar.strftime(dt, "%m-%d %H:%M")

  defp status_class("delivered"), do: "font-medium text-success"
  defp status_class("pending"), do: "font-medium text-warning"
  defp status_class("failed"), do: "font-medium text-error"
  defp status_class(_), do: "font-medium"
end
