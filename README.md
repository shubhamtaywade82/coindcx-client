# coindcx-client

`coindcx-client` is a CoinDCX-specific Ruby gem scaffold that keeps the Delta-style layering without copying Delta's endpoint layout.

## Design goals

- keep transport, auth, resources, models, and websockets separate
- model CoinDCX namespaces explicitly: public, spot, margin, user, transfers, and futures
- keep typed models only for the payloads that benefit from a small facade
- preserve CoinDCX websocket constraints instead of flattening them into a generic websocket abstraction
- make rate limiting endpoint-aware for documented spot order endpoints

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
```

## Installation

```ruby
gem "coindcx-client"
```

For local development:

```bash
bundle install
```

## Configuration

```ruby
require "coindcx"

CoinDCX.configure do |config|
  config.api_key = ENV.fetch("COINDCX_API_KEY")
  config.api_secret = ENV.fetch("COINDCX_API_SECRET")
  config.socket_io_backend_factory = -> { MySocketIoBackend.new }
end
```

The websocket backend must respond to `connect(url)`, `emit(event, payload)`, `on(event, &block)`, and `disconnect`.

## REST usage

```ruby
client = CoinDCX.client

client.public.market_data.list_tickers
client.public.market_data.list_market_details
client.public.market_data.list_trades(pair: "B-BTC_USDT", limit: 50)

client.spot.orders.create(
  side: "buy",
  order_type: "limit_order",
  market: "SNTBTC",
  price_per_unit: "0.03244",
  total_quantity: 400
)

client.user.accounts.list_balances
client.transfers.wallets.transfer(
  source_wallet_type: "spot",
  destination_wallet_type: "futures",
  currency_short_name: "USDT",
  amount: 1
)

client.futures.market_data.list_active_instruments(margin_currency_short_names: ["USDT"])
client.futures.market_data.fetch_instrument(pair: "B-BTC_USDT", margin_currency_short_name: "USDT")
client.futures.orders.list(status: "open", margin_currency_short_name: ["USDT"])
```

## Websocket usage

CoinDCX documents Socket.io for websocket access. This gem keeps that boundary explicit.

```ruby
client = CoinDCX.client
prices_channel = CoinDCX::WS::PublicChannels.price_stats(pair: "B-BTC_USDT")

client.ws.connect
client.ws.subscribe_public(channel_name: prices_channel, event_name: "price-change") do |payload|
  puts payload
end
```

Private subscriptions use the documented `coindcx` channel signing flow:

```ruby
client.ws.subscribe_private(event_name: CoinDCX::WS::PrivateChannels::ORDER_UPDATE_EVENT) do |payload|
  puts payload
end
```

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

## Notes

- spot market data stays under `rest/public`
- futures market data lives under `rest/futures`, even when it uses public hosts
- websocket order book parsing is snapshot-oriented and preserves CoinDCX's "up to 50 recent orders" constraint
- the websocket layer refuses to masquerade as a plain websocket client
