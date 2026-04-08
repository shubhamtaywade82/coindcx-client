# Core Usage

## 1. Initialization

```ruby
require 'logger'
require 'coindcx'

CoinDCX.configure do |config|
  config.api_key = ENV.fetch('COINDCX_API_KEY')
  config.api_secret = ENV.fetch('COINDCX_API_SECRET')
  config.logger = Logger.new($stdout)
  config.max_retries = 2
  config.retry_base_interval = 0.25
  config.socket_reconnect_attempts = 3
  config.socket_reconnect_interval = 1.0
end

client = CoinDCX.client
```

## 2. Public APIs

```ruby
tickers = client.public.market_data.list_tickers
markets = client.public.market_data.list_markets
market_details = client.public.market_data.list_market_details
candles = client.public.market_data.list_candles(pair: 'B-BTC_USDT', interval: '1m')
order_book = client.public.market_data.fetch_order_book(pair: 'B-BTC_USDT')
trades = client.public.market_data.list_trades(pair: 'B-BTC_USDT', limit: 50)
```

## 3. Private APIs

### Spot orders

```ruby
order = client.spot.orders.create(
  side: 'buy',
  order_type: 'limit_order',
  market: 'SNTBTC',
  price_per_unit: '0.03244',
  total_quantity: 400
)
```

### Balances and account info

```ruby
balances = client.user.accounts.list_balances
info = client.user.accounts.fetch_info
```

### Wallet transfers

```ruby
transfer = client.transfers.wallets.transfer(
  source_wallet_type: 'spot',
  destination_wallet_type: 'futures',
  currency_short_name: 'USDT',
  amount: 1
)
```

## 4. Futures APIs

```ruby
active_instruments = client.futures.market_data.list_active_instruments(
  margin_currency_short_names: ['USDT']
)

instrument = client.futures.market_data.fetch_instrument(
  pair: 'B-BTC_USDT',
  margin_currency_short_name: 'USDT'
)

futures_order_book = client.futures.market_data.fetch_order_book(
  instrument: 'B-BTC_USDT',
  depth: 50
)

positions = client.futures.positions.list
```

## 5. WebSocket Usage

```ruby
ws = client.ws
channel = CoinDCX::WS::PublicChannels.price_stats(pair: 'B-BTC_USDT')

ws.connect

ws.subscribe_public(channel_name: channel, event_name: 'price-change') do |data|
  puts data
end
```

### Private stream usage

```ruby
ws.subscribe_private(
  event_name: CoinDCX::WS::PrivateChannels::ORDER_UPDATE_EVENT
) do |data|
  puts data
end
```

## 6. Error Handling

```ruby
begin
  client.spot.orders.create(
    side: 'buy',
    order_type: 'limit_order',
    market: 'SNTBTC',
    price_per_unit: '0.03244',
    total_quantity: 400
  )
rescue CoinDCX::Errors::AuthError => e
  warn("authentication failed: #{e.message}")
rescue CoinDCX::Errors::RateLimitError => e
  warn("rate limited: #{e.message}")
rescue CoinDCX::Errors::RequestError => e
  warn("request failed: #{e.message}")
end
```

## 7. Critical Rules

- Keep the gem as an API client only
- Keep strategy, risk, and position tracking in your app
- Prefer websocket feeds over polling when CoinDCX provides them
- Route all authenticated calls through the provided resource classes, not ad-hoc HTTP code
