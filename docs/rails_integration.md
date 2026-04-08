# Rails Integration

## Architecture

```
CoinDCX Gem -> Adapter Layer -> AlgoTradingApi -> Strategy -> Execution
```

## 1. Initializer

```ruby
# config/initializers/coindcx.rb
CoinDCX.configure do |config|
  config.api_key = ENV.fetch('COINDCX_API_KEY')
  config.api_secret = ENV.fetch('COINDCX_API_SECRET')
  config.logger = Rails.logger
  config.max_retries = 2
  config.retry_base_interval = 0.25
  config.socket_reconnect_attempts = 3
  config.socket_reconnect_interval = 1.0
end

COINDCX_CLIENT = CoinDCX.client
```

## 2. Adapter Layer (MANDATORY)

Do **not** call the gem directly from controllers, jobs, or domain services.

```ruby
# app/services/brokers/coindcx/client.rb
module Brokers
  module Coindcx
    class Client
      def initialize(client: COINDCX_CLIENT)
        @client = client
      end

      def place_limit_buy(market:, price_per_unit:, total_quantity:)
        @client.spot.orders.create(
          side: 'buy',
          order_type: 'limit_order',
          market: market,
          price_per_unit: price_per_unit,
          total_quantity: total_quantity,
          client_order_id: SecureRandom.uuid
        )
      end

      def fetch_ltp(market:)
        @client.public.market_data.list_tickers.find { |ticker| ticker.market == market }
      end

      def balances
        @client.user.accounts.list_balances
      end
    end
  end
end
```

## 3. WebSocket -> Event System

Replace a polling-first flow with an event-driven flow:

```
CoinDCX WS -> EventBus -> Positions::Manager -> Exit Engine
```

The gem does not ship an `EventBus`; keep it in the Rails app.

```ruby
# config/initializers/event_bus.rb
module EventBus
  @listeners = Hash.new { |hash, key| hash[key] = [] }

  class << self
    def subscribe(event, &block)
      @listeners[event] << block
    end

    def publish(event, payload)
      @listeners[event].each { |listener| listener.call(payload) }
    end
  end
end
```

```ruby
# config/initializers/coindcx_ws.rb
Thread.new do
  ws = COINDCX_CLIENT.ws
  channel = CoinDCX::WS::PublicChannels.price_stats(pair: 'B-BTC_USDT')

  ws.connect
  ws.subscribe_public(channel_name: channel, event_name: 'price-change') do |data|
    EventBus.publish(:ltp_update, data)
  end
end
```

## 4. LTP Cache (CRITICAL)

```ruby
# app/services/positions/ltp_cache.rb
module Positions
  class LtpCache
    def self.update(symbol, price)
      Rails.cache.write("ltp:#{symbol}", price)
    end

    def self.get(symbol)
      Rails.cache.read("ltp:#{symbol}")
    end
  end
end
```

```ruby
EventBus.subscribe(:ltp_update) do |payload|
  symbol = payload.fetch('s', 'UNKNOWN')
  price = payload.fetch('p', payload['last_price'])
  Positions::LtpCache.update(symbol, price)
end
```

## 5. Risk Manager Integration

```ruby
ltp = Positions::LtpCache.get(symbol)

if ltp && ltp <= stop_loss
  exit_position
end
```

## 6. Order Execution Flow

```
Signal -> Adapter -> CoinDCX -> Order ID -> Track -> WS updates -> Exit
```

## 7. Critical Rules

- Never call the gem directly from controllers
- Always go through the adapter layer
- Send websocket events into your app event bus
- Prefer websocket market data over polling when available
- Keep all strategy and risk logic in Rails, not in the gem
- Persist `client_order_id` in your Rails app before calling create-order endpoints
- Treat websocket events as at-least-once delivery and deduplicate in the app if needed
