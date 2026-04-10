# coindcx-client

`coindcx-client` is a CoinDCX-specific Ruby client built from a layered exchange-client architecture rather than a thin wrapper.

## Documentation

- [Docs index](./docs/README.md)
- [Core usage](./docs/core.md)
- [Rails integration](./docs/rails_integration.md)
- [Standalone trading bot](./docs/standalone_bot.md)

## Design goals

- keep transport, auth, resources, models, and websockets separate
- model CoinDCX namespaces explicitly: public, spot, margin, user, transfers, and futures
- keep the gem stateless and leave strategy, position tracking, and risk logic to the host app
- preserve CoinDCX websocket constraints instead of flattening them into a generic websocket abstraction
- enforce endpoint-aware rate limiting at the transport boundary
- fail with structured errors that trading code can classify cleanly

## Structure

```
lib/coindcx.rb
lib/coindcx/version.rb
lib/coindcx/configuration.rb
lib/coindcx/client.rb
lib/coindcx/transport/
lib/coindcx/errors/
lib/coindcx/auth/
lib/coindcx/rest/
lib/coindcx/ws/
lib/coindcx/models/
lib/coindcx/contracts/
lib/coindcx/utils/
docs/
```

## Installation

```ruby
gem 'coindcx-client'
```

For local development:

```bash
bundle install
```

## Configuration

```ruby
require 'logger'
require 'coindcx'

CoinDCX.configure do |config|
  config.api_key = ENV.fetch('COINDCX_API_KEY')
  config.api_secret = ENV.fetch('COINDCX_API_SECRET')
  config.logger = Logger.new($stdout)

  # HTTP retry tuning
  config.max_retries = 2
  config.retry_base_interval = 0.25
  config.market_data_retry_budget = 2
  config.private_read_retry_budget = 1
  config.idempotent_order_retry_budget = 1

  # Socket reconnect tuning
  config.socket_reconnect_attempts = 5
  config.socket_reconnect_interval = 1.0
  config.socket_heartbeat_interval = 10.0
  config.socket_liveness_timeout = 60.0

  # Critical order-endpoint protection
  config.circuit_breaker_threshold = 3
  config.circuit_breaker_cooldown = 30.0
end
```

By default the websocket layer uses `socket.io-client-simple`. You can still override the backend with `socket_io_backend_factory` when you need a custom adapter.

## REST usage

```ruby
client = CoinDCX.client

client.public.market_data.list_tickers
client.public.market_data.list_market_details
client.public.market_data.list_trades(pair: 'B-BTC_USDT', limit: 50)

client.spot.orders.create(
  side: 'buy',
  order_type: 'limit_order',
  market: 'SNTBTC',
  price_per_unit: '0.03244',
  total_quantity: 400,
  client_order_id: SecureRandom.uuid
)

client.user.accounts.list_balances
client.transfers.wallets.transfer(
  source_wallet_type: 'spot',
  destination_wallet_type: 'futures',
  currency_short_name: 'USDT',
  amount: 1
)

client.futures.market_data.list_active_instruments(margin_currency_short_names: ['USDT'])
client.futures.market_data.fetch_instrument(pair: 'B-BTC_USDT', margin_currency_short_name: 'USDT')
client.futures.market_data.current_prices
client.futures.market_data.stats(pair: 'B-BTC_USDT')
client.futures.market_data.conversions
client.futures.orders.list(status: 'open', margin_currency_short_name: ['USDT'])
client.futures.orders.list_trades(page: 1, size: 50)

client.funding.orders.list
client.funding.orders.lend(currency_short_name: 'USDT', amount: '10')
client.funding.orders.settle(id: 'funding-order-id')
```

## Websocket usage

CoinDCX documents Socket.io for websocket access. This gem keeps that boundary explicit and now tracks connection state, heartbeat liveness, private auth renewal, and subscription replay after reconnects.

Socket.IO often delivers **multiple data arguments** after the event name (for example a channel string plus the quote object). The client **coalesces** those into a single Hash (merging multiple Hash frames) before invoking your block, so handlers always see one payload object.

Live streams frequently wrap quotes as `{ "event" => "price-change", "data" => "<JSON string>" }`. The client **parses** that `data` string and **merges** the inner object to the top level before dispatch, so fields like `p` and `s` are directly on the hash passed to your block.

**Fan-out:** one underlying listener is registered per `event_name` (for example all `price-change` subscriptions share it). Every handler for that event runs on **every** message. For multiple instruments, filter using payload hints such as `s`, `pair`, or `market` (see `scripts/futures_ws_subscription_smoke.rb`).

```ruby
client = CoinDCX.client
prices_channel = CoinDCX::WS::PublicChannels.price_stats(pair: 'B-BTC_USDT')

client.ws.connect
client.ws.subscribe_public(channel_name: prices_channel, event_name: 'price-change') do |payload|
  puts payload
end
```

## Trading safety rules

- Always supply `client_order_id` when placing orders. The gem will not retry mutable order creation without it.
- Persist `client_order_id` in your host application so a timeout can be reconciled safely.
- Order create and transfer requests validate required fields before sending them to CoinDCX.
- WebSocket subscriptions are replayed automatically after reconnect, and private subscriptions rebuild auth payloads on every reconnect.
- WebSocket delivery is `at_least_once`. Consumers must tolerate duplicates after reconnect.
- The gem does not guarantee lossless recovery of events missed while CoinDCX was disconnected.

Private subscriptions use the documented `coindcx` channel signing flow:

```ruby
client.ws.subscribe_private(event_name: CoinDCX::WS::PrivateChannels::ORDER_UPDATE_EVENT) do |payload|
  puts payload
end
```

## Error handling

The transport raises structured errors so calling code can branch intentionally without parsing strings:

- `CoinDCX::Errors::AuthError`
- `CoinDCX::Errors::RateLimitError`
- `CoinDCX::Errors::RetryableRateLimitError`
- `CoinDCX::Errors::RemoteValidationError`
- `CoinDCX::Errors::UpstreamServerError`
- `CoinDCX::Errors::TransportError`
- `CoinDCX::Errors::CircuitOpenError`
- `CoinDCX::Errors::RequestError`
- `CoinDCX::Errors::SocketConnectionError`
- `CoinDCX::Errors::SocketAuthenticationError`
- `CoinDCX::Errors::SocketStateError`

Every API error exposes normalized metadata through `status`, `category`, `code`, `request_context`, and `retryable`.

## Rate limiting

`CoinDCX::Configuration` ships with named buckets for authenticated endpoint families and enforces them before the request is sent.

Read and write paths are separated so market data traffic does not consume order-placement capacity. Private endpoints require an explicit bucket definition.

Spot order buckets include:

- `spot_create_order_multiple`
- `spot_create_order`
- `spot_cancel_all`
- `spot_order_status_multiple`
- `spot_order_status`
- `spot_cancel_multiple_by_id`
- `spot_cancel_order`
- `spot_active_order`
- `spot_active_order_count`
- `spot_trade_history`
- `spot_edit_price`

Additional private endpoint families ship with conservative defaults until exchange-specific limits are confirmed.

## Stateless boundary

This gem is intentionally limited to:

- API calls
- signing
- socket connection management
- lightweight parsing and typed facades

This gem intentionally does **not** own:

- position tracking
- order lifecycle orchestration outside the API response shape
- strategy logic
- risk management
- application caching
- persistence of idempotency keys
- reconciliation of missed websocket events after downtime

## Notes

- spot market data stays under `rest/public`
- futures market data lives under `rest/futures`, even when it uses public hosts
- websocket order book parsing is snapshot-oriented and preserves CoinDCX's "up to 50 recent orders" constraint
- the websocket layer uses Socket.io and does not masquerade as a plain websocket client
- release tags are expected to be immutable once published
