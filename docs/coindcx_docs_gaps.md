# CoinDCX Docs Coverage Gaps (REST + WebSocket)

## REST endpoint gaps

- `POST /exchange/v1/funding/fetch_orders`
- `POST /exchange/v1/funding/lend`
- `POST /exchange/v1/funding/settle`
- `POST /exchange/v1/derivatives/futures/trades`
- `GET /market_data/v3/current_prices/futures/rt`
- `GET /api/v1/derivatives/futures/data/stats`
- `GET /api/v1/derivatives/futures/data/conversions`

## WebSocket gaps

- No SDK constants/helpers for documented public stream event names:
  - `candlestick`
  - `depth-snapshot`
  - `depth-update`
  - `new-trade`
  - `price-change`
- Futures public socket docs reuse these event names, so the same event-constant gap applies there.
