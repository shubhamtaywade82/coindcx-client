# CoinDCX Ruby Client

Production-grade Ruby client for CoinDCX REST + Socket.io APIs.

## Docs

- [Core Usage](./core.md)
- [Rails Integration](./rails_integration.md)
- [Standalone Trading Bot](./standalone_bot.md)

## Philosophy

- Stateless client
- No trading logic
- Deterministic execution
- Event-driven compatible

## Notes

These docs use the current implemented `CoinDCX` namespace and API surface from this repository.
Application-level concerns like `EventBus`, position tracking, caching, and exit logic remain outside the gem.
