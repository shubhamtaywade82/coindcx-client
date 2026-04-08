# Standalone Trading Bot

## Architecture

```
WS Feed -> Strategy Engine -> Command -> Execution -> Risk -> Exit
```

## 1. Boot

```ruby
require 'logger'
require 'coindcx'

CoinDCX.configure do |config|
  config.api_key = ENV.fetch('COINDCX_API_KEY')
  config.api_secret = ENV.fetch('COINDCX_API_SECRET')
  config.logger = Logger.new($stdout)
  config.socket_reconnect_attempts = 5
  config.socket_heartbeat_interval = 10.0
  config.socket_liveness_timeout = 60.0
end

client = CoinDCX.client
ws = client.ws
```

Keep the event bus in the bot process, not in the gem:

```ruby
class EventBus
  def initialize
    @listeners = Hash.new { |hash, key| hash[key] = [] }
  end

  def subscribe(event, &block)
    @listeners[event] << block
  end

  def publish(event, payload)
    @listeners[event].each { |listener| listener.call(payload) }
  end
end

event_bus = EventBus.new
```

## 2. Subscribe Market

```ruby
channel = CoinDCX::WS::PublicChannels.price_stats(pair: 'B-BTC_USDT')

ws.connect
ws.subscribe_public(channel_name: channel, event_name: 'price-change') do |message|
  event_bus.publish(:tick, message)
end
```

## 3. Strategy Engine

```ruby
class Strategy
  def initialize(event_bus:, execution:)
    @execution = execution
    event_bus.subscribe(:tick) { |data| on_tick(data) }
  end

  def on_tick(data)
    price = BigDecimal(data.fetch('p', data.fetch('last_price')).to_s)
    execute_trade(price) if breakout?(price)
  end

  private

  def breakout?(price)
    price > BigDecimal('100.0')
  end

  def execute_trade(price)
    @execution.call(price: price)
  end
end
```

## 4. Execution (Command Pattern in the Bot)

```ruby
class ExecuteTrade
  def initialize(client:)
    @client = client
  end

  def call(price:)
    client_order_id = SecureRandom.uuid

    @client.spot.orders.create(
      side: 'buy',
      order_type: 'limit_order',
      market: 'SNTBTC',
      price_per_unit: price.to_s,
      total_quantity: 1,
      client_order_id: client_order_id
    )
  end
end
```

## 5. Risk Manager

```ruby
class RiskManager
  def initialize(entry_price)
    @entry_price = entry_price
  end

  def stop_loss
    @entry_price * BigDecimal('0.98')
  end
end
```

## 6. Exit Logic

```ruby
risk_manager = RiskManager.new(BigDecimal('100.0'))

event_bus.subscribe(:tick) do |data|
  price = BigDecimal(data.fetch('p', data.fetch('last_price')).to_s)
  exit_position if price <= risk_manager.stop_loss
end
```

## 7. Resilience

Your bot loop should explicitly handle:

- websocket reconnects
- duplicate ticks
- order failures after the gem exhausts its bounded retry policy
- stale data timeouts

The gem delivers websocket subscriptions with at-least-once semantics after reconnect. Treat duplicate ticks as normal and de-duplicate at your event boundary when your strategy needs exactly-once behavior.

The gem will reconnect sockets, renew private-channel auth, enforce endpoint throttles, and normalize transport errors, but your bot still owns strategy-safe recovery.

Operator intervention is still required when:

- the websocket reaches the `failed` state after bounded reconnect attempts
- the order circuit breaker opens on repeated create-order failures
- upstream validation errors indicate your request contract is wrong

## 8. Minimal Loop

```ruby
execution = ExecuteTrade.new(client: client)
Strategy.new(event_bus: event_bus, execution: execution)

sleep
```
