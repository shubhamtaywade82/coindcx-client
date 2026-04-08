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

### Runtime contract

- REST requests are validated locally before serialization when the gem knows the required boundary rules.
- Mutable order endpoints are never auto-retried unless the caller supplies an idempotency key such as `client_order_id`.
- WebSocket delivery is at-least-once across reconnects. Consumers must tolerate duplicate events.
- Public and private subscriptions are replayed after reconnect. Private subscriptions regenerate auth payloads on every reconnect.
- The gem does not guarantee durable event replay from CoinDCX. If the socket dies, missed events during downtime are the host app's responsibility.
