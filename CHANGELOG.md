# Changelog

## Unreleased

- Added funding REST namespace (`client.funding.orders`) with `fetch_orders`, `lend`, and `settle` endpoint coverage.
- Futures REST now covers `/exchange/v1/derivatives/futures/trades`, `/market_data/v3/current_prices/futures/rt`, `/api/v1/derivatives/futures/data/stats`, and `/api/v1/derivatives/futures/data/conversions`.
- WebSocket public channels now expose constants for documented events: `candlestick`, `depth-snapshot`, `depth-update`, `new-trade`, and `price-change`.
- Updated `docs/coindcx_docs_gaps.md` to reflect that the previously identified REST/WebSocket gaps are now covered in the gem.
- Futures WebSocket: `PublicChannels` adds `futures_candlestick`, `futures_order_book`, `current_prices_futures`, and `CURRENT_PRICES_FUTURES_*` constants; `PrivateChannels` adds `DF_POSITION_UPDATE_EVENT` and `DF_ORDER_UPDATE_EVENT`. New `scripts/futures_sockets_smoke.rb`; `futures_ws_subscription_smoke.rb` private mode now uses df-* events.
- Add `scripts/spot_sockets_smoke.rb` to exercise all documented Spot public streams (and private `coindcx` events when API credentials are set); `examples/spot_socket.js` adds `all-public-spot` for the same matrix in Node; `docs/core.md` links the Ruby smoke script.
- Default websocket `socket_io_connect_options` uses `EIO: 3` so the bundled `socket.io-client-simple` backend matches CoinDCX stream and official socket.io-client 2.x (Engine.IO v4 was never compatible with that parser).
- Futures `validate_futures_create!` accepts `total_quantity` (derivatives create style) alongside `quantity` and `size`.
- Enforced order-placement idempotency: Spot/Margin/Futures create contracts now require `client_order_id`, transport rejects unsafe create requests without it, and batch spot create checks every order in `orders` for an idempotency key.

All notable changes to `coindcx-client` should be documented in this file.

The release workflow expects a section whose heading matches the version tag being
published, for example:

## 0.1.0

- Describe the externally visible change
- Call out any breaking behavior or operator action

Release notes should include rollback guidance when a bad release is published:

- yank command or RubyGems rollback action
- follow-up patch version plan
- postmortem owner and summary
