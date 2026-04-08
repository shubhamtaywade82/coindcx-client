# AGENT.md — CoinDCX Client (Pattern-Enforced Architecture)

## 1. Design Philosophy

- patterns are tools, not goals
- each pattern must solve a real constraint
- zero speculative abstraction

## 2. Approved Design Patterns (STRICT)

Only these patterns are allowed.

| Pattern | Mandatory | Reason |
| --- | --- | --- |
| Factory | yes | resource/client creation |
| Strategy | yes | auth + retry + rate limit |
| Adapter | yes | HTTP + Socket.io isolation |
| Observer | yes | WebSocket event system |
| Command | yes | order execution encapsulation |
| Template Method | yes | REST execution pipeline |
| Builder | yes | request construction |
| Decorator | yes | logging + retry wrapping |
| Singleton | limited | config only |
| Facade | yes | client interface |
| State | limited | WS only, connection lifecycle |

Everything else -> reject.

## 3. Pattern Mapping to System

### 3.1 Facade Pattern -> Client

Purpose:

- expose clean interface
- `client.public.markets`
- `client.spot.place_order(...)`
- `client.ws.subscribe(...)`

Implementation:

```ruby
module Coindcx
  class Client
    def public
      @public ||= Rest::Public::Facade.new(http_client)
    end

    def spot
      @spot ||= Rest::Spot::Facade.new(http_client)
    end

    def ws
      @ws ||= Ws::Facade.new(ws_client)
    end
  end
end
```

### 3.2 Factory Pattern -> Resource Creation

Purpose:

- decouple instantiation

```ruby
module Coindcx
  class ResourceFactory
    def self.build(type, client)
      case type
      when :markets then Rest::Public::Markets.new(client)
      when :orders  then Rest::Spot::Orders.new(client)
      else raise "Unknown resource"
      end
    end
  end
end
```

### 3.3 Strategy Pattern -> Auth / Retry / RateLimit

Purpose:

- swap runtime behavior without branching chaos

Auth Strategy:

```ruby
class HmacAuthStrategy
  def sign(payload, secret)
    OpenSSL::HMAC.hexdigest('SHA256', secret, payload.to_json)
  end
end
```

Retry Strategy:

```ruby
class ExponentialBackoffStrategy
  def execute
    retries = 0
    begin
      yield
    rescue => e
      raise if retries >= 3
      sleep(2 ** retries)
      retries += 1
      retry
    end
  end
end
```

### 3.4 Adapter Pattern -> HTTP + Socket.io

Purpose:

- shield external libraries

HTTP Adapter:

```ruby
class FaradayAdapter
  def call(method, url, payload, headers)
    Faraday.public_send(method, url) do |req|
      req.headers = headers
      req.body = payload.to_json if method == :post
    end
  end
end
```

Socket Adapter:

```ruby
class SocketIoAdapter
  def initialize(url)
    @socket = SocketIO::Client::Simple.connect(url)
  end

  def emit(event, payload)
    @socket.emit(event, payload)
  end

  def on(event, &block)
    @socket.on(event, &block)
  end
end
```

### 3.5 Observer Pattern -> WebSocket Events (CRITICAL)

Reference: Observer Pattern Ruby example

Purpose:

- event-driven system (mandatory for trading)

Subject:

```ruby
module Coindcx
  module Ws
    class EventBus
      def initialize
        @listeners = {}
      end

      def subscribe(event, listener)
        @listeners[event] ||= []
        @listeners[event] << listener
      end

      def publish(event, data)
        (@listeners[event] || []).each do |listener|
          listener.call(data)
        end
      end
    end
  end
end
```

Usage:

```ruby
event_bus.subscribe(:ltp_update, ->(data) {
  puts data
})

event_bus.publish(:ltp_update, payload)
```

### 3.6 Command Pattern -> Order Execution

Purpose:

- encapsulate actions (important for retries + audit)

```ruby
class PlaceOrderCommand
  def initialize(client, params)
    @client = client
    @params = params
  end

  def execute
    @client.post("/orders", @params)
  end
end
```

### 3.7 Template Method -> HTTP Pipeline

Purpose:

- standardize request flow

```ruby
class BaseRequest
  def execute
    validate
    payload = build_payload
    signed = sign(payload)
    response = send_request(signed)
    parse(response)
  end

  def validate; end
  def build_payload; end
  def sign(payload); payload; end
  def send_request(payload); end
  def parse(response); end
end
```

### 3.8 Builder Pattern -> Request Construction

Purpose:

- avoid hash chaos

```ruby
class OrderBuilder
  def initialize
    @params = {}
  end

  def symbol(val); @params[:symbol] = val; self; end
  def side(val); @params[:side] = val; self; end
  def quantity(val); @params[:quantity] = val; self; end

  def build
    raise "Missing fields" unless @params[:symbol]
    @params
  end
end
```

### 3.9 Decorator Pattern -> Logging / Retry

Purpose:

- add behavior without modifying core

```ruby
class LoggingDecorator
  def initialize(client, logger)
    @client = client
    @logger = logger
  end

  def call(*args)
    start = Time.now
    result = @client.call(*args)
    @logger.info("Latency: #{Time.now - start}")
    result
  end
end
```

### 3.10 State Pattern -> WebSocket Lifecycle

Purpose:

- handle connection transitions cleanly

```ruby
class ConnectedState
  def handle(context)
    # active
  end
end

class ReconnectingState
  def handle(context)
    context.reconnect
  end
end
```

## 4. Pattern Anti-Abuse Rules

Reject if:

- pattern used without clear constraint
- multiple patterns solving same problem
- inheritance chains > 2 levels
- over-engineered builders for simple calls

## 5. Critical Integration Insight

Where Observer connects to your system:

- `CoinDCX WS -> EventBus -> AlgoTradingApi -> Exit Engine`

This is how you replicate:

- Dhan WebSocket feed
- ActiveCache updates
- real-time exit logic

## 6. What NOT to implement (explicit)

- Repository pattern (no DB)
- Service layer (anti-pattern for this gem)
- CQRS (overkill)
- Event sourcing (belongs to trading system)
- ActiveRecord-style models

## 7. Final Enforcement Rule

> Every pattern must map to a production failure mode.

If it doesn't: -> remove it.

## 8. Next Step

If proceeding correctly, the next move is:

- bootstrap with patterns wired from day 1

I can generate:

- full gem scaffold
- all patterns pre-wired
- working REST + WS base
- RSpec coverage

Say:

`bootstrap pattern gem`
