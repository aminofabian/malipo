defmodule MalipoWeb.Admin.IntentLive do
  @moduledoc """
  Super-admin intent inspector — one intent's lifecycle, its rail attempts, the
  outbox events it produced, and the C2B receipt that settled it. Route:
  `/admin/intents/:id`. Read only.
  """

  use MalipoWeb, :live_view

  alias Malipo.Admin

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Admin.intent_detail(id) do
      {:ok, detail} ->
        {:ok,
         socket
         |> assign(:page_title, "Intent")
         |> assign(:detail, detail)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Intent not found")
         |> push_navigate(to: ~p"/admin/intents")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:intents} admin={@current_admin}>
      <.link
        navigate={~p"/admin/intents"}
        class="text-sm text-base-content/60 hover:text-base-content"
      >
        ← Back to intents
      </.link>

      <div class="mt-4 mb-6 flex flex-wrap items-start justify-between gap-4">
        <div>
          <div class="flex items-center gap-3">
            <h1 class="text-2xl font-semibold tracking-tight tabular-nums">
              {@detail.intent.amount |> Decimal.to_string()} {@detail.intent.currency}
            </h1>
            <span class={"badge " <> status_class(@detail.intent.status)}>
              {@detail.intent.status}
            </span>
          </div>
          <p class="mt-1 font-mono text-xs text-base-content/50">{@detail.intent.id}</p>
        </div>
      </div>

      <section class="mb-8">
        <dl class="grid gap-x-8 gap-y-3 text-sm sm:grid-cols-2 lg:grid-cols-3">
          <.field label="Business" value={@detail.intent.business_id} mono />
          <.field label="Attribution" value={attribution(@detail)} />
          <.field label="Destination id" value={destination_id(@detail.intent) || "—"} mono />
          <.field label="Account ref sent" value={account_reference(@detail)} mono />
          <.field label="Rail" value={@detail.intent.rail} />
          <.field label="Payer MSISDN" value={mask(@detail.intent.payer_msisdn)} mono />
          <.field label="Idempotency key" value={@detail.intent.idempotency_key} mono />
          <.field label="Checkout request id" value={@detail.intent.checkout_request_id || "—"} mono />
          <.field label="Merchant request id" value={@detail.intent.merchant_request_id || "—"} mono />
          <.field label="Receipt" value={@detail.intent.receipt || "—"} mono />
          <.field label="Created" value={fmt(@detail.intent.inserted_at)} />
          <.field label="Prompted" value={fmt(@detail.intent.prompted_at)} />
          <.field label="Expires" value={fmt(@detail.intent.expires_at)} />
          <.field label="Settled" value={fmt(@detail.intent.settled_at)} />
          <.field
            label="Failed / expired"
            value={fmt(@detail.intent.failed_at || @detail.intent.expired_at)}
          />
        </dl>

        <div
          :if={@detail.intent.failure_kind || @detail.intent.failure_message}
          class="mt-4 rounded-md border border-error/30 bg-error/5 p-3 text-sm"
        >
          <p class="font-medium text-error">
            Failure: {@detail.intent.failure_kind || "—"}
            <span :if={@detail.intent.failure_provider_code} class="font-mono text-xs">
              ({@detail.intent.failure_provider_code})
            </span>
          </p>
          <p :if={@detail.intent.failure_message} class="mt-1 text-base-content/70">
            {@detail.intent.failure_message}
          </p>
        </div>
      </section>

      <section class="mb-8 space-y-3 border-t border-base-300 pt-6">
        <h2 class="text-sm font-semibold">Attempts ({length(@detail.attempts)})</h2>

        <p :if={@detail.attempts == []} class="text-sm text-base-content/50">
          No rail attempts recorded.
        </p>

        <div :if={@detail.attempts != []} class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr class="text-base-content/50">
                <th>#</th>
                <th>Status</th>
                <th>Checkout request id</th>
                <th>Account ref</th>
                <th>When</th>
                <th>Failure</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={attempt <- @detail.attempts}>
                <td class="tabular-nums">{attempt.attempt_number}</td>
                <td>
                  <span class={"badge badge-sm " <> status_class(attempt.status)}>{attempt.status}</span>
                </td>
                <td class="font-mono text-xs">{attempt.checkout_request_id || "—"}</td>
                <td class="font-mono text-xs">{attempt_account_reference(attempt)}</td>
                <td class="whitespace-nowrap text-xs text-base-content/50">
                  {fmt(attempt.inserted_at)}
                </td>
                <td class="text-xs">
                  <span :if={attempt.failure_kind} class="text-error">{attempt.failure_kind}</span>
                  <span :if={attempt.failure_message} class="mt-0.5 block text-base-content/60">
                    {attempt.failure_message}
                  </span>
                  <span
                    :if={is_nil(attempt.failure_kind) && is_nil(attempt.failure_message)}
                    class="text-base-content/40"
                  >
                    —
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section class="mb-8 space-y-3 border-t border-base-300 pt-6">
        <h2 class="text-sm font-semibold">Outbox events ({length(@detail.events)})</h2>

        <p :if={@detail.events == []} class="text-sm text-base-content/50">
          No settlement events for this intent.
        </p>

        <div :if={@detail.events != []} class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr class="text-base-content/50">
                <th>Event</th>
                <th>Status</th>
                <th>Attempts</th>
                <th>When</th>
                <th>Last error</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={event <- @detail.events}>
                <td>
                  <span class="font-medium">{event.event}</span>
                  <span class="mt-0.5 block font-mono text-xs text-base-content/50">{event.event_id}</span>
                </td>
                <td>
                  <span class={"badge badge-sm " <> status_class(event.status)}>{event.status}</span>
                </td>
                <td class="tabular-nums">{event.attempts}</td>
                <td class="whitespace-nowrap text-xs text-base-content/50">
                  {fmt(event.inserted_at)}
                </td>
                <td class="max-w-[16rem] truncate text-xs text-error/80" title={event.last_error}>
                  {event.last_error || "—"}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section :if={@detail.receipt} class="space-y-3 border-t border-base-300 pt-6">
        <h2 class="text-sm font-semibold">Matched C2B receipt</h2>
        <dl class="grid gap-x-8 gap-y-3 text-sm sm:grid-cols-2 lg:grid-cols-3">
          <.field label="Trans ID" value={@detail.receipt.trans_id} mono />
          <.field label="Amount" value={money(@detail.receipt.amount, @detail.receipt.currency)} />
          <.field label="Shortcode" value={@detail.receipt.shortcode || "—"} mono />
          <.field label="Payer" value={mask(@detail.receipt.payer_msisdn)} mono />
          <.field label="Payer name" value={@detail.receipt.payer_name || "—"} />
          <.field label="Bill ref" value={@detail.receipt.bill_ref || "—"} mono />
        </dl>
      </section>
    </Layouts.admin>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :mono, :boolean, default: false

  defp field(assigns) do
    ~H"""
    <div>
      <dt class="text-base-content/50">{@label}</dt>
      <dd class={["mt-0.5", @mono && "font-mono text-xs"]}>{@value}</dd>
    </div>
    """
  end

  defp attribution(detail) do
    id = destination_id(detail.intent)

    cond do
      detail.destination -> Admin.destination_label(detail.destination)
      is_binary(id) -> "Attributed to a destination that no longer exists"
      true -> "Not attributed"
    end
  end

  defp account_reference(detail) do
    detail.attempts
    |> List.last()
    |> case do
      %{request_payload: %{"account_reference" => ref}} when is_binary(ref) -> ref
      _ -> "—"
    end
  end

  defp attempt_account_reference(%{request_payload: %{"account_reference" => ref}})
       when is_binary(ref),
       do: ref

  defp attempt_account_reference(_attempt), do: "—"

  defp destination_id(intent) do
    case intent.context do
      %{"settlement_destination_id" => id} when is_binary(id) -> id
      _ -> nil
    end
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
  defp fmt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp status_class(status) when status in ["settled", "delivered"], do: "badge-success"
  defp status_class(status) when status in ["failed", "unmatched"], do: "badge-error"

  defp status_class(status) when status in ["prompted", "pending", "sent", "pending_at_provider"],
    do: "badge-warning"

  defp status_class("expired"), do: "badge-ghost"
  defp status_class(_status), do: "badge-ghost"
end
