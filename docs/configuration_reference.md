# Configuration Reference

This page summarizes the practical configuration surface exposed by `CoinDCX.configure` so teams can tune behavior quickly by environment and workload.

## Baseline template

```ruby
CoinDCX.configure do |config|
  config.api_key = ENV.fetch('COINDCX_API_KEY')
  config.api_secret = ENV.fetch('COINDCX_API_SECRET')
  config.logger = Logger.new($stdout)

  # HTTP resilience
  config.max_retries = 2
  config.retry_base_interval = 0.25
  config.market_data_retry_budget = 2
  config.private_read_retry_budget = 1
  config.idempotent_order_retry_budget = 1

  # websocket resilience
  config.socket_reconnect_attempts = 5
  config.socket_reconnect_interval = 1.0
  config.socket_heartbeat_interval = 10.0
  config.socket_liveness_timeout = 60.0

  # write-path safety
  config.circuit_breaker_threshold = 3
  config.circuit_breaker_cooldown = 30.0
end
```

## Settings by responsibility

### Credentials and identity

- `api_key`: CoinDCX API key for authenticated endpoints and private streams
- `api_secret`: secret used for HMAC signing

### HTTP retry controls

- `max_retries`: global retry cap
- `retry_base_interval`: backoff base interval in seconds
- `market_data_retry_budget`: retries allowed for market-data family endpoints
- `private_read_retry_budget`: retries allowed for private read endpoints
- `idempotent_order_retry_budget`: retries allowed for create/update order paths when idempotency conditions are safe

### WebSocket controls

- `socket_reconnect_attempts`: bounded reconnect attempts before failed state
- `socket_reconnect_interval`: reconnect base delay in seconds
- `socket_heartbeat_interval`: heartbeat cadence
- `socket_liveness_timeout`: quiet-stream timeout before connection considered stale
- `socket_io_connect_options`: low-level socket.io options (default includes `EIO: 3` for compatibility)

### Circuit breaker controls

- `circuit_breaker_threshold`: number of consecutive failures before opening breaker on critical order routes
- `circuit_breaker_cooldown`: cooldown seconds before allowing attempts again

## Environment presets

### Development / staging preset

Faster feedback, lower timeout sensitivity:

```ruby
config.max_retries = 1
config.retry_base_interval = 0.15
config.socket_reconnect_attempts = 3
config.socket_liveness_timeout = 90.0
```

### Production preset

Higher resilience, stronger write-path safety:

```ruby
config.max_retries = 2
config.retry_base_interval = 0.25
config.socket_reconnect_attempts = 5
config.socket_liveness_timeout = 60.0
config.circuit_breaker_threshold = 3
config.circuit_breaker_cooldown = 30.0
```

## Practical tuning guidance

- Increase `market_data_retry_budget` only if you can tolerate stale snapshots.
- Keep `idempotent_order_retry_budget` conservative unless your app persists `client_order_id` reliably.
- For noisy networks, increase reconnect attempts first before increasing heartbeat timeouts.
- If create-order endpoints flap, lower breaker threshold cautiously and alert operators on open-state transitions.
