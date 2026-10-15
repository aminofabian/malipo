defmodule MalipoWeb.Admin.DashboardLive do
  @moduledoc "Super-admin overview. Route: `/admin`."

  use MalipoWeb, :live_view

  alias Malipo.Admin
  alias Malipo.ConnectAccounts

  @recent_transaction_limit 8
  @recent_account_limit 5
  @test_email_domains ~w(example.com example.org example.net)
  @chart_bar_px 112
  @chart_min_px 8
  @tx_filters ~w(all failed)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Overview")
     |> assign(:tx_filter, "all")
     |> assign(:hide_tests, false)
     |> load()}
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, load(socket)}

  def handle_event("show_transactions", %{"filter" => filter}, socket)
      when filter in @tx_filters do
    {:noreply, assign(socket, :tx_filter, filter)}
  end

  def handle_event("toggle_test_accounts", _params, socket) do
    {:noreply, assign(socket, :hide_tests, not socket.assigns.hide_tests)}
  end

  defp load(socket) do
    series = Admin.settled_volume_series()

    socket
    |> assign(:overview, Admin.overview())
    |> assign(:series, series)
    |> assign(:series_total, sum_series(series))
    |> assign(:accounts, ConnectAccounts.list_recent(@recent_account_limit))
    |> assign(:transactions, Admin.list_transactions(@recent_transaction_limit))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:dashboard} admin={@current_admin}>
      <div class="mx-auto flex w-full max-w-[1180px] flex-col gap-4">
        <.overview_header generated_at={@overview.generated_at} />
        <.metric_grid overview={@overview} series_total={@series_total} />
        <.insight_row
          series={@series}
          series_total={@series_total}
          overview={@overview}
          failed_recent={failed_count(@transactions)}
        />
        <.activity_row
          transactions={@transactions}
          tx_filter={@tx_filter}
          accounts={@accounts}
          hide_tests={@hide_tests}
          now={@overview.generated_at}
        />
      </div>
    </Layouts.admin>
    """
  end

  attr :generated_at, DateTime, required: true

  defp overview_header(assigns) do
    ~H"""
    <header class="mb-2 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 class="text-3xl font-semibold tracking-tight">Overview</h1>
        <p class="mt-1 text-sm text-[var(--admin-muted)]">
          Money movement across Malipo: accounts, intents, till receipts, outbox.
        </p>
      </div>
      <div class="flex items-center gap-3">
        <p class="text-xs text-[var(--admin-faint)]">Updated {format_clock(@generated_at)}</p>
        <button
          type="button"
          phx-click="refresh"
          class="inline-flex items-center gap-2 rounded-full bg-[var(--admin-button)] px-4 py-2 text-sm font-medium text-[var(--admin-button-text)] active:scale-[0.98]"
        >
          <.icon name="hero-arrow-path" class="size-4" /> Refresh
        </button>
      </div>
    </header>
    """
  end

  attr :overview, :map, required: true
  attr :series_total, :any, required: true

  defp metric_grid(assigns) do
    ~H"""
    <section class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <.metric
        label="Settled volume · 24h"
        kind={:money}
        figure={money_amount(@overview.intents.settled_volume_24h)}
      >
        <:sub>KES {money_amount(@series_total)} in the last 7 days</:sub>
      </.metric>
      <.metric
        label="Settled volume · all time"
        kind={:money}
        figure={money_amount(@overview.intents.settled_volume)}
      >
        <:sub>{@overview.intents.settled} settled intents</:sub>
      </.metric>
      <.metric label="Connect accounts" kind={:count} figure={to_string(@overview.accounts.total)}>
        <:sub>+{@overview.accounts.new_7d} in the last 7 days</:sub>
      </.metric>
      <.metric label="Intents · 24h" kind={:count} figure={to_string(@overview.intents.last_24h)}>
        <:sub>
          <span>{@overview.intents.open} open</span>
          <span class={failed_chip(@overview.intents.failed)}>
            {@overview.intents.failed} failed
          </span>
        </:sub>
      </.metric>
      <.metric label="Till receipts" kind={:count} figure={to_string(@overview.till.total)}>
        <:sub>{till_detail(@overview.till)}</:sub>
      </.metric>
      <.metric
        label="Outbox · pending"
        kind={:count}
        figure={to_string(@overview.outbox.pending)}
        healthy={healthy_outbox?(@overview.outbox)}
      >
        <:sub>{@overview.outbox.failed} failed · {@overview.outbox.delivered} delivered</:sub>
      </.metric>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :kind, :atom, required: true
  attr :figure, :string, required: true
  attr :healthy, :boolean, default: false
  slot :sub

  defp metric(assigns) do
    ~H"""
    <article class="rounded-2xl border border-[var(--admin-line)] bg-[var(--admin-card)] px-5 py-4">
      <div class="flex items-start justify-between gap-3">
        <p class="text-[11px] font-semibold uppercase tracking-[0.08em] text-[var(--admin-muted)]">
          {@label}
        </p>
        <p
          :if={@healthy}
          class="inline-flex items-center gap-1 text-xs font-medium text-[var(--admin-green)]"
        >
          <.icon name="hero-check" class="size-3.5" /> Healthy
        </p>
      </div>
      <p class="mt-3 leading-none">
        <span
          :if={@kind == :money}
          class="mr-1.5 align-middle text-sm font-medium text-[var(--admin-muted)]"
        >
          KES
        </span>
        <span class="align-middle text-[1.75rem] font-semibold tracking-tight tabular-nums">{@figure}</span>
      </p>
      <div class="mt-2 flex flex-wrap items-center gap-2 text-xs text-[var(--admin-muted)]">
        {render_slot(@sub)}
      </div>
    </article>
    """
  end

  attr :series, :list, required: true
  attr :series_total, :any, required: true
  attr :overview, :map, required: true
  attr :failed_recent, :integer, required: true

  defp insight_row(assigns) do
    assigns = assign(assigns, :backlog, outbox_backlog(assigns.overview.outbox))

    ~H"""
    <section class="grid gap-4 lg:grid-cols-5">
      <.volume_chart series={@series} total={money_amount(@series_total)} />
      <article class="rounded-2xl border border-[var(--admin-line)] bg-[var(--admin-card)] px-5 py-4 lg:col-span-2">
        <h2 class="text-sm font-semibold">Needs attention</h2>
        <div class="mt-2 divide-y divide-[var(--admin-line)]">
          <.attention
            count={@overview.intents.failed}
            tone={:problem}
            title="Failed intents"
            detail="Review why payments did not settle"
          >
            <.link navigate={~p"/admin/intents"} class="text-sm font-medium text-[var(--admin-green)]">
              Review
            </.link>
          </.attention>
          <.attention
            count={@failed_recent}
            tone={:problem}
            title="Failed STK pushes"
            detail="In the recent transactions below"
          >
            <button
              type="button"
              phx-click="show_transactions"
              phx-value-filter="failed"
              class="text-sm font-medium text-[var(--admin-green)]"
            >
              Filter
            </button>
          </.attention>
          <.attention
            count={@backlog}
            tone={:clear}
            title="Outbox backlog"
            detail={outbox_detail(@overview.outbox)}
          >
            <.link
              :if={@backlog > 0}
              navigate={~p"/admin/outbox"}
              class="text-sm font-medium text-[var(--admin-green)]"
            >
              Review
            </.link>
          </.attention>
        </div>
      </article>
    </section>
    """
  end

  attr :series, :list, required: true
  attr :total, :string, required: true

  defp volume_chart(assigns) do
    assigns = assign(assigns, :peak, peak_amount(assigns.series))

    ~H"""
    <article
      class="rounded-2xl border border-[var(--admin-line)] bg-[var(--admin-card)] px-5 py-4 lg:col-span-3"
      aria-label={"Settled volume for the last 7 days, total KES #{@total}"}
    >
      <div class="flex items-baseline justify-between gap-4">
        <h2 class="text-sm font-semibold">Settled volume · last 7 days</h2>
        <p class="text-xs text-[var(--admin-muted)]">Total KES {@total}</p>
      </div>
      <div class="mt-6 flex h-44 items-end gap-2 border-b border-[var(--admin-line)]">
        <div
          :for={day <- @series}
          class="flex h-full min-w-0 flex-1 flex-col items-center justify-end"
        >
          <span
            :if={Decimal.compare(day.amount, 0) == :gt}
            class="mb-1 text-[11px] font-medium text-[var(--admin-muted)]"
          >
            {compact_amount(day.amount)}
          </span>
          <div
            class="w-7 max-w-full rounded-t-md bg-[var(--admin-bar)]"
            style={"height: #{bar_height(day.amount, @peak)}px"}
          />
        </div>
      </div>
      <div class="mt-2 flex gap-2">
        <p
          :for={day <- @series}
          class="min-w-0 flex-1 text-center text-[11px] text-[var(--admin-faint)]"
        >
          {day_label(day.date)}
        </p>
      </div>
    </article>
    """
  end

  attr :count, :integer, required: true
  attr :tone, :atom, required: true
  attr :title, :string, required: true
  attr :detail, :string, required: true
  slot :inner_block

  defp attention(assigns) do
    ~H"""
    <div class="flex items-start gap-4 py-4">
      <p class={[
        "w-10 shrink-0 text-2xl font-semibold tabular-nums leading-none",
        attention_tone(@count, @tone)
      ]}>
        {@count}
      </p>
      <div class="min-w-0 flex-1">
        <p class="text-sm font-medium">{@title}</p>
        <p class="mt-0.5 text-xs text-[var(--admin-muted)]">{@detail}</p>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :transactions, :list, required: true
  attr :tx_filter, :string, required: true
  attr :accounts, :list, required: true
  attr :hide_tests, :boolean, required: true
  attr :now, DateTime, required: true

  defp activity_row(assigns) do
    assigns =
      assigns
      |> assign(:filters, @tx_filters)
      |> assign(:shown, shown_transactions(assigns.transactions, assigns.tx_filter))
      |> assign(:visible_accounts, visible_accounts(assigns.accounts, assigns.hide_tests))
      |> assign(:failed_count, failed_count(assigns.transactions))

    ~H"""
    <section class="grid gap-4 lg:grid-cols-5">
      <article class="min-w-0 rounded-2xl border border-[var(--admin-line)] bg-[var(--admin-card)] px-5 py-4 lg:col-span-3">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 class="text-sm font-semibold">Recent transactions</h2>
          <div class="flex items-center gap-2">
            <button
              :for={filter <- @filters}
              type="button"
              phx-click="show_transactions"
              phx-value-filter={filter}
              class={filter_classes(@tx_filter, filter)}
            >
              {filter_label(filter, length(@transactions), @failed_count)}
            </button>
            <.link
              navigate={~p"/admin/transactions"}
              class="text-sm font-medium text-[var(--admin-green)]"
            >
              View all
            </.link>
          </div>
        </div>
        <.transaction_table transactions={@shown} filter={@tx_filter} now={@now} />
      </article>

      <article class="min-w-0 rounded-2xl border border-[var(--admin-line)] bg-[var(--admin-card)] px-5 py-4 lg:col-span-2">
        <div class="flex items-center justify-between gap-3">
          <h2 class="text-sm font-semibold">Newest accounts</h2>
          <div class="flex items-center gap-2">
            <button
              type="button"
              phx-click="toggle_test_accounts"
              class="rounded-lg border border-[var(--admin-line)] px-2.5 py-1 text-xs font-medium hover:bg-[var(--admin-hover)]"
            >
              {if @hide_tests, do: "Show test", else: "Hide test"}
            </button>
            <.link
              navigate={~p"/admin/accounts"}
              class="text-sm font-medium text-[var(--admin-green)]"
            >
              View all
            </.link>
          </div>
        </div>
        <.account_list accounts={@visible_accounts} hide_tests={@hide_tests} now={@now} />
      </article>
    </section>
    """
  end

  attr :transactions, :list, required: true
  attr :filter, :string, required: true
  attr :now, DateTime, required: true

  defp transaction_table(assigns) do
    ~H"""
    <p :if={@transactions == []} class="py-10 text-center text-sm text-[var(--admin-muted)]">
      {empty_transactions(@filter)}
    </p>
    <div :if={@transactions != []} class="mt-4 overflow-x-auto">
      <table class="w-full text-left text-sm">
        <thead>
          <tr class="text-[10px] font-semibold uppercase tracking-[0.08em] text-[var(--admin-faint)]">
            <th class="pb-2 pr-3 font-semibold">When</th>
            <th class="pb-2 pr-3 font-semibold">Type</th>
            <th class="pb-2 pr-3 font-semibold">Amount</th>
            <th class="pb-2 pr-3 font-semibold">Reference</th>
            <th class="pb-2 font-semibold">Status</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={tx <- @transactions} class="border-t border-[var(--admin-line)]">
            <td class="py-3 pr-3 whitespace-nowrap">
              <p>{format_stamp(tx.at)}</p>
              <p class="text-[11px] text-[var(--admin-faint)]">{relative_day(tx.at, @now)}</p>
            </td>
            <td class="py-3 pr-3">
              <span class={["rounded px-1.5 py-0.5 text-[10px] font-semibold", kind_classes(tx.kind)]}>
                {String.upcase(tx.kind)}
              </span>
            </td>
            <td class="py-3 pr-3 whitespace-nowrap tabular-nums">
              <span class="font-semibold">{money_amount(tx.amount)}</span>
              <span class="ml-1 text-xs text-[var(--admin-muted)]">{tx.currency}</span>
            </td>
            <td class="max-w-[9rem] truncate py-3 pr-3 font-mono text-xs" title={tx.reference}>
              {tx.reference || "-"}
            </td>
            <td class="py-3">
              <span class={[
                "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium",
                status_classes(tx.status)
              ]}>
                <.icon :if={settled_status?(tx.status)} name="hero-check" class="size-3" />
                <.icon :if={tx.status == "failed"} name="hero-x-mark" class="size-3" />
                {status_label(tx.status)}
              </span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :accounts, :list, required: true
  attr :hide_tests, :boolean, required: true
  attr :now, DateTime, required: true

  defp account_list(assigns) do
    ~H"""
    <p :if={@accounts == []} class="py-10 text-center text-sm text-[var(--admin-muted)]">
      {if @hide_tests, do: "Test accounts are hidden.", else: "No accounts yet."}
    </p>
    <ul :if={@accounts != []} class="mt-2 divide-y divide-[var(--admin-line)]">
      <li :for={account <- @accounts} class="flex items-start justify-between gap-3 py-3">
        <div class="min-w-0">
          <p class="truncate text-sm">
            {account.email}
            <span
              :if={test_account?(account)}
              class="ml-1 rounded bg-[var(--admin-chip)] px-1.5 py-0.5 text-[10px] font-semibold tracking-wide text-[var(--admin-muted)]"
            >
              TEST
            </span>
          </p>
          <p class="truncate font-mono text-[11px] text-[var(--admin-faint)]">
            {account.business_id}
          </p>
        </div>
        <div class="shrink-0 text-right text-[11px] text-[var(--admin-faint)]">
          <p>{relative_day(account.inserted_at, @now)}</p>
          <p>{format_stamp(account.inserted_at)}</p>
        </div>
      </li>
    </ul>
    """
  end

  defp sum_series(series) do
    Enum.reduce(series, Decimal.new(0), fn day, total -> Decimal.add(total, day.amount) end)
  end

  defp failed_count(transactions), do: Enum.count(transactions, &(&1.status == "failed"))

  defp shown_transactions(transactions, "failed") do
    Enum.filter(transactions, &(&1.status == "failed"))
  end

  defp shown_transactions(transactions, _filter), do: transactions

  defp visible_accounts(accounts, true), do: Enum.reject(accounts, &test_account?/1)
  defp visible_accounts(accounts, false), do: accounts

  defp test_account?(%{email: email}) when is_binary(email) do
    email
    |> String.downcase()
    |> String.split("@")
    |> List.last()
    |> then(&(&1 in @test_email_domains))
  end

  defp test_account?(_account), do: false

  defp healthy_outbox?(%{pending: 0, failed: 0}), do: true
  defp healthy_outbox?(_outbox), do: false

  defp outbox_backlog(%{pending: pending, failed: failed}), do: pending + failed

  defp outbox_detail(%{pending: 0, failed: 0}), do: "Nothing pending or failed"

  defp outbox_detail(%{pending: pending, failed: failed}) do
    "#{pending} pending · #{failed} failed"
  end

  defp till_detail(%{total: 0, matched: matched, unmatched: unmatched}) do
    "No receipts yet · #{matched} matched · #{unmatched} unmatched"
  end

  defp till_detail(%{matched: matched, unmatched: unmatched}) do
    "#{matched} matched · #{unmatched} unmatched"
  end

  defp empty_transactions("failed"), do: "No failed payments in this list."
  defp empty_transactions(_filter), do: "No transactions yet."

  defp filter_label("all", total, _failed), do: "All (#{total})"
  defp filter_label("failed", _total, failed), do: "Failed (#{failed})"

  defp filter_classes(current, current) do
    "rounded-full bg-[var(--admin-button)] px-3 py-1 text-xs font-medium text-[var(--admin-button-text)]"
  end

  defp filter_classes(_current, _filter) do
    "rounded-full border border-[var(--admin-line)] bg-[var(--admin-card)] px-3 py-1 text-xs font-medium"
  end

  defp failed_chip(0), do: nil

  defp failed_chip(_count) do
    "rounded-full bg-[var(--admin-danger-soft)] px-1.5 py-0.5 font-medium text-[var(--admin-danger)]"
  end

  defp attention_tone(0, :clear), do: "text-[var(--admin-green)]"
  defp attention_tone(0, _tone), do: "text-[var(--admin-muted)]"
  defp attention_tone(_count, _tone), do: "text-[var(--admin-danger)]"

  defp settled_status?(status), do: status in ["settled", "matched", "delivered"]

  defp status_classes(status) when status in ["settled", "matched", "delivered"] do
    "bg-[var(--admin-ok-soft)] text-[var(--admin-green-deep)]"
  end

  defp status_classes(status) when status in ["failed", "unmatched"] do
    "bg-[var(--admin-danger-soft)] text-[var(--admin-danger)]"
  end

  defp status_classes(_status), do: "bg-[var(--admin-chip)] text-[var(--admin-muted)]"

  defp kind_classes("stk"), do: "bg-[var(--admin-stk-soft)] text-[var(--admin-stk)]"
  defp kind_classes(_kind), do: "bg-[var(--admin-chip)] text-[var(--admin-muted)]"

  defp status_label(status) when is_binary(status) do
    status |> String.replace("_", " ") |> String.capitalize()
  end

  defp peak_amount(series) do
    Enum.reduce(series, Decimal.new(0), fn %{amount: amount}, peak ->
      case Decimal.compare(amount, peak) do
        :gt -> amount
        _ -> peak
      end
    end)
  end

  defp bar_height(%Decimal{} = amount, %Decimal{} = peak) do
    cond do
      Decimal.compare(amount, 0) != :gt -> 0
      Decimal.compare(peak, 0) != :gt -> 0
      true -> scaled_bar(amount, peak)
    end
  end

  defp scaled_bar(amount, peak) do
    pixels =
      amount
      |> Decimal.div(peak)
      |> Decimal.mult(@chart_bar_px)
      |> Decimal.round(0)
      |> Decimal.to_integer()

    max(pixels, @chart_min_px)
  end

  defp compact_amount(%Decimal{} = amount) do
    rounded = Decimal.round(amount, 2)
    normalized = Decimal.normalize(rounded)

    if normalized.exp >= 0 do
      rounded |> Decimal.round(0) |> Decimal.to_string(:normal)
    else
      Decimal.to_string(rounded, :normal)
    end
  end

  defp money_amount(%Decimal{} = amount) do
    amount |> Decimal.round(2) |> Decimal.to_string(:normal)
  end

  defp money_amount(other), do: to_string(other)

  defp day_label(%Date{} = date) do
    "#{Calendar.strftime(date, "%a")} #{date.day}"
  end

  defp format_clock(%DateTime{} = datetime) do
    datetime
    |> Admin.to_nairobi()
    |> Calendar.strftime("%I:%M %p")
    |> String.trim_leading("0")
  end

  defp format_stamp(%DateTime{} = datetime) do
    local = Admin.to_nairobi(datetime)
    "#{Calendar.strftime(local, "%b")} #{local.day}, #{Calendar.strftime(local, "%H:%M")}"
  end

  defp relative_day(%DateTime{} = datetime, %DateTime{} = now) do
    days = Date.diff(nairobi_date(now), nairobi_date(datetime))

    cond do
      days <= 0 -> "today"
      days == 1 -> "1d ago"
      true -> "#{days}d ago"
    end
  end

  defp nairobi_date(%DateTime{} = datetime) do
    datetime |> Admin.to_nairobi() |> DateTime.to_date()
  end
end
