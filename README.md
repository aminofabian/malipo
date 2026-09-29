# Malipo — Daraja payments service

Elixir/Phoenix OTP app that will own **Daraja money movement** for Kiosk.ke:
STK push/query, C2B ingest, credential vault, intent lifecycle, outbox.

The Spring monolith (`../../backend`) keeps owning what a payment *means*
(sales, tabs, orders, wallets). See
[`../docs/PAYMENTS_MICROSERVICE_ELIXIR_DARAJA_SCOPE.md`](../docs/PAYMENTS_MICROSERVICE_ELIXIR_DARAJA_SCOPE.md).

## Stack

| Piece | Choice |
|---|---|
| Language | Elixir 1.18 / OTP 28 |
| Web | Phoenix 1.8 + LiveView |
| DB | PostgreSQL (`malipo_dev`) |
| Jobs | Oban (wired next) |
| HTTP | Finch (`Malipo.Finch`) |
| Secrets | Cloak (`Malipo.Vault`) |

## Quick start

```bash
cd malipo/service
mix deps.get
mix ecto.create
mix ecto.migrate
mix test
mix phx.server
```

App listens on [http://127.0.0.1:4000](http://127.0.0.1:4000).

Database defaults (override in `config/dev.exs` or env via `config/runtime.exs`):

- host `localhost`
- user/password `postgres` / `postgres`
- database `malipo_dev`

## Layout (in progress)

```
lib/malipo/
├── rails/          Rail behaviour, Failure, Classify, Daraja (Finch)
├── intents/        STK state machine + Oban poller/sweeper
├── webhooks/       Daraja ingest (persist → Oban → settle)
├── till/           C2B till receipts (match or unmatched outbox)
├── vault/          Cloak-encrypted platform Daraja settings
├── outbox/         monolith event dispatch (Oban)
├── msisdn.ex       phone normalisation
└── vault.ex        Cloak vault
```

## Operations

Intents created before per-destination attribution existed have no destination id.
Attribute them once after deploy (idempotent — safe to re-run):

```bash
mix malipo.backfill_attribution
```

In a release (no Mix), use `eval`:

```bash
bin/malipo eval "Malipo.Admin.backfill_destination_attribution()"
```

The same action is available as **Backfill attribution** on the super-admin
Merchants page (`/admin/merchants`). New intents are attributed automatically at
creation.

## Status

Scaffolded + Oban + intents + Daraja adapter + platform vault + webhooks +
outbox + internal intent API + health probes + **C2B till receipts**
(`till_receipts`, match-by-BillRef / unmatched → `till_receipt.unmatched`).

**Super-admin console** at `/admin/*` (LiveView, session login): overview
dashboard, unified transactions, an intent inspector, Connect accounts, till
receipts, outbox, merchants, a team screen for DB-backed console operators, and
platform Daraja credentials. See
[`../console/README.md`](../console/README.md).

Elixir-only. Next: Broadway ingest under load, or rail-health read API.
# malipo
