# AGENT.md — CoinDCX Ruby Client (coindcx-client)

## 1. Purpose

Build a production-grade Ruby client gem for CoinDCX that:

- fully supports REST + Socket.io APIs
- is deterministic, testable, and failure-safe
- is suitable for live trading integration
- strictly separates transport from trading logic

This gem is **NOT** a trading system.

## 2. Non-Negotiable Constraints

### 2.1 Architecture Boundary

| Layer | Responsibility |
| --- | --- |
| Gem | API communication only |
| AlgoTradingApi | strategy, execution, risk |

Violation = reject PR.

### 2.2 No Hidden State

- No caching
- No position tracking
- No strategy logic
- No global mutable state

All state must be:

- explicit
- injectable
- testable

### 2.3 Socket Implementation Constraint

CoinDCX uses Socket.io, not raw WebSocket.

Rules:

- Do NOT use faye-websocket
- Do NOT reuse Dhan WebSocket logic
- MUST use Socket.io-compatible client

If this is wrong -> system unusable.

### 2.4 Determinism

All methods must be:

- side-effect predictable
- retry-safe
- idempotent where applicable

## 3. Architecture

Reference baseline: delta_exchange gem

### 3.1 Directory Structure

```
lib/
  coindcx.rb
  coindcx/version.rb
  coindcx/configuration.rb

  coindcx/client.rb

  coindcx/transport/
    http_client.rb

  coindcx/auth/
    signer.rb

  coindcx/rest/
    public/
    spot/
    futures/
    users/

  coindcx/ws/
    client.rb
    connection_manager.rb
    channels/
    handlers/

  coindcx/errors/
  coindcx/contracts/
  coindcx/utils/
```

## 4. Core Components

### 4.1 Client (Entry Point)

```ruby
Coindcx::Client.new(
  api_key:,
  secret:,
  logger:,
  timeout:
)
```

Responsibilities:

- compose dependencies
- expose resource accessors
- no business logic

### 4.2 Transport Layer

Responsibilities:

- HTTP execution
- retries
- rate limiting
- error normalization

Rules:

- no endpoint-specific logic
- no parsing beyond JSON

### 4.3 Auth Layer

CoinDCX uses HMAC SHA256.

Requirements:

- deterministic signature generation
- timestamp injection
- payload canonicalization

### 4.4 REST Resources

Each resource maps 1:1 to API group.

Example:

- `client.public.markets`
- `client.spot.orders`
- `client.futures.positions`

Rules:

- no orchestration
- no retries (handled in transport)
- no cross-resource calls

### 4.5 WebSocket Layer

| Component | Responsibility |
| --- | --- |
| Client | connection |
| ConnectionManager | reconnect logic |
| Channels | subscription contracts |
| Handlers | message parsing |

### 4.6 Models (Optional)

Only introduce if:

- parsing complexity exists
- domain invariants required

Otherwise return raw hashes.

## 5. Error Handling

All errors must be normalized.

- `Coindcx::Errors::ApiError`
- `Coindcx::Errors::AuthError`
- `Coindcx::Errors::RateLimitError`
- `Coindcx::Errors::NetworkError`

Rules:

- no raw Faraday errors leak
- no silent failures
- always include:
  - `request_id` (if available)
  - `endpoint`
  - `payload`

## 6. Rate Limiting

Mandatory.

CoinDCX has endpoint-specific limits.

Implementation requirements:

- token bucket or sliding window
- per-endpoint configuration
- blocking throttle (NOT async drop)

## 7. Retry Strategy

Only retry when:

- network failure
- 5xx errors
- rate limit (with delay)

Never retry:

- auth failure
- validation errors
- 4xx (except 429)

## 8. Logging

Required fields:

- endpoint
- latency
- status
- retry_count

Rules:

- no sensitive data (API keys, signatures)
- structured logging preferred

## 9. WebSocket Design

### 9.1 Connection Manager

Must handle:

- reconnect with backoff
- resubscription
- auth re-init

### 9.2 Message Handling

- parse once
- emit normalized payload
- no business logic

### 9.3 Failure Handling

- disconnect -> reconnect
- stale connection -> reset
- auth failure -> fail fast

## 10. Contracts (Validation)

Use strict validation for:

- order placement
- required params
- enum values

Fail early.

## 11. Testing Strategy

### 11.1 RSpec Coverage

Minimum:

- 90% coverage
- all public methods tested

### 11.2 Test Types

| Type | Tool |
| --- | --- |
| Unit | RSpec |
| HTTP | WebMock |
| WS | mock socket |
| Integration | optional |

### 11.3 Required Cases

- success
- API error
- network failure
- retry behavior
- rate limit

## 12. Forbidden Patterns

- service objects inside gem
- global singletons
- silent rescue
- implicit retries
- mixing REST + WS logic
- trading logic inside gem

## 13. Extension Rules

Adding new endpoints:

1. create resource class
2. add method
3. add contract (if needed)
4. add tests
5. do not modify transport unless required

## 14. Integration Contract (with AlgoTradingApi)

Gem returns:

- raw or normalized API data

Rails app handles:

- signals
- entries
- exits
- SL/TP logic
- risk

## 15. Definition of Done

Feature is complete only if:

- [ ] API call works against real endpoint
- [ ] RSpec coverage added
- [ ] failure scenarios tested
- [ ] logging present
- [ ] no architectural violation

## 16. Initial Milestones

### Phase 1

- HTTP client
- auth
- public endpoints

### Phase 2

- private REST (orders, balances)

### Phase 3

- WebSocket (public)

### Phase 4

- WebSocket (private)

### Phase 5

- resilience (retry, reconnect)

## 17. Critical Risks

1. Socket.io mismatch  
   Wrong implementation -> entire system breaks
2. Rate limits ignored  
   -> API bans
3. Silent failures  
   -> trading losses
4. Over-abstraction  
   -> slow development + brittle code

## 18. Review Checklist (PR Gate)

Reject PR if:

- architecture violated
- missing tests
- hidden state introduced
- WS implemented incorrectly
- retries not controlled

## 19. Naming Conventions

- `Coindcx::Rest::Public::Markets`
- `Coindcx::Ws::Client`
- `Coindcx::Transport::HttpClient`

Consistency required.

## 20. Final Principle

> This gem is an execution-grade API client, not a framework.

- minimal
- predictable
- robust

Everything else belongs outside.
