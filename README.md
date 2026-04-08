# coindcx-client

`coindcx-client` is a CoinDCX-specific Ruby gem scaffold built from a layered exchange-client architecture rather than a thin wrapper.

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
- make rate limiting endpoint-aware for documented spot order endpoints
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

  # Socket reconnect tuning
  config.socket_reconnect_attempts = 3
  config.socket_reconnect_interval = 1.0
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
  total_quantity: 400
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
client.futures.orders.list(status: 'open', margin_currency_short_name: ['USDT'])
```

## Websocket usage

CoinDCX documents Socket.io for websocket access. This gem keeps that boundary explicit and reconnects using configurable retry settings.

```ruby
client = CoinDCX.client
prices_channel = CoinDCX::WS::PublicChannels.price_stats(pair: 'B-BTC_USDT')

client.ws.connect
client.ws.subscribe_public(channel_name: prices_channel, event_name: 'price-change') do |payload|
  puts payload
end
```

Private subscriptions use the documented `coindcx` channel signing flow:

```ruby
client.ws.subscribe_private(event_name: CoinDCX::WS::PrivateChannels::ORDER_UPDATE_EVENT) do |payload|
  puts payload
end
```

## Error handling

The transport raises structured errors so calling code can respond intentionally:

- `CoinDCX::Errors::AuthError`
- `CoinDCX::Errors::RateLimitError`
- `CoinDCX::Errors::RequestError`
- `CoinDCX::Errors::SocketConnectionError`

## Rate limiting

`CoinDCX::Configuration` ships with the documented spot order limits as named buckets:

- `spot_create_order_multiple`
- `spot_create_order`
- `spot_cancel_all`
- `spot_order_status_multiple`
- `spot_order_status`
- `spot_cancel_multiple_by_id`
- `spot_cancel_order`
- `spot_active_order`
- `spot_edit_price`

Unknown endpoints are intentionally left unbucketed until their limits are confirmed.

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

## Notes

- spot market data stays under `rest/public`
- futures market data lives under `rest/futures`, even when it uses public hosts
- websocket order book parsing is snapshot-oriented and preserves CoinDCX's "up to 50 recent orders" constraint
- the websocket layer uses Socket.io and does not masquerade as a plain websocket client
