# coindcx-client

`coindcx-client` is a CoinDCX-specific Ruby SDK focused on fast integration, safer defaults, and predictable behavior for production trading systems.

## Quick start (5 minutes)

1. **Install the gem**

   ```ruby
   gem 'coindcx-client'
   ```

2. **Configure credentials and runtime knobs**

   ```ruby
   require 'logger'
   require 'coindcx'

   CoinDCX.configure do |config|
     config.api_key = ENV.fetch('COINDCX_API_KEY')
     config.api_secret = ENV.fetch('COINDCX_API_SECRET')
     config.logger = Logger.new($stdout)

     # retries
     config.max_retries = 2
     config.retry_base_interval = 0.25

     # websocket health + reconnect
     config.socket_reconnect_attempts = 5
     config.socket_reconnect_interval = 1.0
     config.socket_heartbeat_interval = 10.0
     config.socket_liveness_timeout = 60.0

     # critical write-path protection
     config.circuit_breaker_threshold = 3
     config.circuit_breaker_cooldown = 30.0
   end
   ```

3. **Create client and call a public endpoint**

   ```ruby
   client = CoinDCX.client
   puts client.public.market_data.list_tickers.first
   ```

4. **Place a private order with idempotency**

   ```ruby
   require 'securerandom'

   client.spot.orders.create(
     side: 'buy',
     order_type: 'limit_order',
     market: 'SNTBTC',
     price_per_unit: '0.03244',
     total_quantity: 400,
     client_order_id: SecureRandom.uuid
   )
   ```

5. **Subscribe to live prices**

   ```ruby
   prices_channel = CoinDCX::WS::PublicChannels.price_stats(pair: 'B-BTC_USDT')

   client.ws.connect
   client.ws.subscribe_public(channel_name: prices_channel, event_name: 'price-change') do |payload|
     puts payload
   end
   ```

## Documentation

- [Docs index](./docs/README.md)
- [Core usage](./docs/core.md)
- [Configuration reference](./docs/configuration_reference.md)
- [Use-case playbook](./docs/use_case_playbook.md)
- [Rails integration](./docs/rails_integration.md)
- [Standalone trading bot](./docs/standalone_bot.md)

## Why this SDK as a first choice for CoinDCX

- CoinDCX namespaces are modeled explicitly (public, spot, margin, user, transfers, futures, funding)
- Built-in request validation for high-risk write paths
- Endpoint-family rate limiting to protect order capacity
- Structured error classes for deterministic retry/abort branches
- WebSocket reconnect, liveness checks, private auth refresh, and subscription replay
- Stateless boundary so your app can own strategy/risk/persistence cleanly

## Developer fast path by use case

- **Backend API service**: start with `docs/core.md` + `docs/configuration_reference.md`
- **Rails app**: start with `docs/rails_integration.md`
- **Standalone bot/worker**: start with `docs/standalone_bot.md`
- **Endpoint or stream coverage planning**: start with `docs/use_case_playbook.md`

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

## WebSocket usage

CoinDCX documents Socket.io for websocket access. This SDK keeps that boundary explicit and tracks connection state, heartbeat liveness, private auth renewal, and subscription replay after reconnect.

Socket.IO may deliver **multiple data arguments** after the event name. The client coalesces those frames into a single payload object.

Live streams often wrap quotes as `{ "event" => "price-change", "data" => "<JSON string>" }`. The client parses and merges the inner object so keys like `p` and `s` are available directly.

```ruby
client = CoinDCX.client
prices_channel = CoinDCX::WS::PublicChannels.price_stats(pair: 'B-BTC_USDT')

client.ws.connect
client.ws.subscribe_public(channel_name: prices_channel, event_name: 'price-change') do |payload|
  # filter by symbol when one event fan-outs multiple instruments
  next unless payload['s'] == 'B-BTC_USDT'

  puts payload
end
```

## Trading safety rules

- Always pass `client_order_id` for mutable order creation APIs.
- Persist your idempotency key in your host app before API submission.
- WebSocket delivery is at-least-once across reconnects; dedupe when needed.
- Reconciliate missed events after downtime via REST snapshots in your app.

## Error handling

The transport raises structured errors so calling code can branch intentionally:

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

## Stateless boundary

This SDK is intentionally limited to API calls, signing, socket management, and lightweight parsing/typed facades.

This SDK intentionally does **not** own strategy, risk, position lifecycle, persistence, or reconciliation policy.
