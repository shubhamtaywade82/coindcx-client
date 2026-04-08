# Changelog

## Unreleased

- Futures WebSocket: `PublicChannels` adds `futures_candlestick`, `futures_order_book`, `current_prices_futures`, and `CURRENT_PRICES_FUTURES_*` constants; `PrivateChannels` adds `DF_POSITION_UPDATE_EVENT` and `DF_ORDER_UPDATE_EVENT`. New `scripts/futures_sockets_smoke.rb`; `futures_ws_subscription_smoke.rb` private mode now uses df-* events.
- Add `scripts/spot_sockets_smoke.rb` to exercise all documented Spot public streams (and private `coindcx` events when API credentials are set); `examples/spot_socket.js` adds `all-public-spot` for the same matrix in Node; `docs/core.md` links the Ruby smoke script.
- Default websocket `socket_io_connect_options` uses `EIO: 3` so the bundled `socket.io-client-simple` backend matches CoinDCX stream and official socket.io-client 2.x (Engine.IO v4 was never compatible with that parser).
- Futures `validate_futures_create!` accepts `total_quantity` (derivatives create style) alongside `quantity` and `size`.

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
