# Use-case Playbook

Action-oriented recipes for common `coindcx-client` integration goals.

## 1) Build a REST-only market scanner quickly

Use when you only need snapshots and no live stream.

```ruby
client = CoinDCX.client

markets = client.public.market_data.list_markets
tickers = client.public.market_data.list_tickers

top = tickers.select { |t| t.volume.to_f > 0 }
             .sort_by { |t| -t.volume.to_f }
             .first(10)

puts top.map(&:market)
```

Tips:
- keep websocket disabled for simple cron scanners
- cache upstream snapshots in your app layer

## 2) Place spot orders safely

Use idempotency keys and persist them before network submission.

```ruby
client_order_id = SecureRandom.uuid
# persist client_order_id in your datastore here

client.spot.orders.create(
  side: 'buy',
  order_type: 'limit_order',
  market: 'SNTBTC',
  price_per_unit: '0.03244',
  total_quantity: 400,
  client_order_id: client_order_id
)
```

Tips:
- never submit mutable create endpoints without `client_order_id`
- on timeout, reconcile by querying order state using your persisted ID

## 3) Run multi-stream websocket consumers

One `event_name` can fan out many instruments; filter in handler.

```ruby
client = CoinDCX.client
ws = client.ws

btc = CoinDCX::WS::PublicChannels.price_stats(pair: 'B-BTC_USDT')
eth = CoinDCX::WS::PublicChannels.price_stats(pair: 'B-ETH_USDT')

ws.connect

[btc, eth].each do |channel|
  ws.subscribe_public(channel_name: channel, event_name: 'price-change') do |payload|
    symbol = payload['s'] || payload['pair'] || payload['market']
    next unless ['B-BTC_USDT', 'B-ETH_USDT'].include?(symbol)

    puts "#{symbol}: #{payload['p'] || payload['last_price']}"
  end
end
```

Tips:
- treat delivery as at-least-once
- dedupe in your application boundary if needed

## 4) Integrate private streams for order lifecycle views

```ruby
ws = CoinDCX.client.ws
ws.connect

ws.subscribe_private(event_name: CoinDCX::WS::PrivateChannels::ORDER_UPDATE_EVENT) do |payload|
  puts payload
end
```

Tips:
- private subscription auth is rebuilt automatically after reconnect
- still reconcile with REST snapshots after prolonged disconnects

## 5) Handle failures deterministically

```ruby
begin
  CoinDCX.client.spot.orders.create(...)
rescue CoinDCX::Errors::RateLimitError => e
  warn("slow down: #{e.message}")
rescue CoinDCX::Errors::RetryableRateLimitError => e
  warn("retryable limit hit: #{e.retryable}")
rescue CoinDCX::Errors::CircuitOpenError => e
  warn("circuit open: #{e.message}")
rescue CoinDCX::Errors::RemoteValidationError => e
  warn("payload rejected: #{e.code}")
end
```

Tips:
- map each error class to explicit policy (`retry`, `abort`, `operator alert`)
- avoid string-matching error bodies
