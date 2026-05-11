# CoinDCX Ruby Client Docs

Production-oriented documentation for the current `coindcx-client` SDK implementation.

## Recommended reading order

1. [Core Usage](./core.md) — quickest path to first successful API and WebSocket calls.
2. [Configuration Reference](./configuration_reference.md) — complete runtime knobs and when to tune them.
3. [Use-case Playbook](./use_case_playbook.md) — implementation patterns for common developer workflows.
4. [Rails Integration](./rails_integration.md) — adapter + event-driven integration in Rails apps.
5. [Standalone Trading Bot](./standalone_bot.md) — event-loop architecture outside Rails.

## What this SDK solves

- CoinDCX REST and Socket.io access with explicit namespace coverage
- Predictable auth/signing and structured error handling
- Guardrails around retries, idempotency, and write-path safety
- Reconnect + subscription replay for websocket workflows

## What remains in your app

- trading strategy decisions
- position/risk lifecycle
- persistence and reconciliation policies
- deduplication rules for at-least-once stream delivery
