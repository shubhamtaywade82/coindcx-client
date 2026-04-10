# frozen_string_literal: true

module CoinDCX
  class Configuration
    DEFAULT_API_BASE_URL = "https://api.coindcx.com"
    DEFAULT_PUBLIC_BASE_URL = "https://public.coindcx.com"
    DEFAULT_SOCKET_BASE_URL = "wss://stream.coindcx.com"
    DEFAULT_USER_AGENT = "coindcx-client/#{VERSION}".freeze
    DEFAULT_PRIVATE_RATE_LIMIT = { limit: 60, period: 60 }.freeze
    DEFAULT_ENDPOINT_RATE_LIMITS = {
      # Public (unauthenticated) endpoints — shared bucket keeps burst bursts off the exchange.
      public_market_data: { limit: 30, period: 1 },
      public_ticker: { limit: 10, period: 1 },
      public_order_book: { limit: 10, period: 1 },
      public_trades: { limit: 10, period: 1 },
      public_candles: { limit: 10, period: 1 },
      spot_create_order_multiple: { limit: 2000, period: 60 },
      spot_create_order: { limit: 2000, period: 60 },
      spot_cancel_all: { limit: 30, period: 60 },
      spot_order_status_multiple: { limit: 2000, period: 60 },
      spot_order_status: { limit: 2000, period: 60 },
      spot_cancel_multiple_by_id: { limit: 300, period: 60 },
      spot_cancel_order: { limit: 2000, period: 60 },
      spot_active_order: { limit: 300, period: 60 },
      spot_active_order_count: DEFAULT_PRIVATE_RATE_LIMIT,
      spot_trade_history: DEFAULT_PRIVATE_RATE_LIMIT,
      spot_edit_price: { limit: 2000, period: 60 },
      futures_list_orders: DEFAULT_PRIVATE_RATE_LIMIT,
      futures_create_order: DEFAULT_PRIVATE_RATE_LIMIT,
      futures_cancel_order: DEFAULT_PRIVATE_RATE_LIMIT,
      futures_edit_order: DEFAULT_PRIVATE_RATE_LIMIT,
      futures_positions_list: DEFAULT_PRIVATE_RATE_LIMIT,
      futures_positions_update_leverage: DEFAULT_PRIVATE_RATE_LIMIT,
      futures_positions_add_margin: DEFAULT_PRIVATE_RATE_LIMIT,
      futures_positions_remove_margin: DEFAULT_PRIVATE_RATE_LIMIT,
      futures_positions_cancel_all_open_orders: DEFAULT_PRIVATE_RATE_LIMIT,
      futures_positions_cancel_all_open_orders_for_position: DEFAULT_PRIVATE_RATE_LIMIT,
      futures_positions_exit: DEFAULT_PRIVATE_RATE_LIMIT,
      futures_positions_create_tpsl: DEFAULT_PRIVATE_RATE_LIMIT,
      futures_positions_transactions: DEFAULT_PRIVATE_RATE_LIMIT,
      futures_positions_cross_margin_details: DEFAULT_PRIVATE_RATE_LIMIT,
      futures_positions_margin_type: DEFAULT_PRIVATE_RATE_LIMIT,
      futures_wallet_transfer: DEFAULT_PRIVATE_RATE_LIMIT,
      futures_wallet_details: DEFAULT_PRIVATE_RATE_LIMIT,
      futures_wallet_transactions: DEFAULT_PRIVATE_RATE_LIMIT,
      margin_create_order: DEFAULT_PRIVATE_RATE_LIMIT,
      margin_list_orders: DEFAULT_PRIVATE_RATE_LIMIT,
      margin_fetch_order: DEFAULT_PRIVATE_RATE_LIMIT,
      margin_cancel_order: DEFAULT_PRIVATE_RATE_LIMIT,
      margin_exit_order: DEFAULT_PRIVATE_RATE_LIMIT,
      margin_edit_target: DEFAULT_PRIVATE_RATE_LIMIT,
      margin_edit_stop_loss: DEFAULT_PRIVATE_RATE_LIMIT,
      margin_edit_trailing_stop_loss: DEFAULT_PRIVATE_RATE_LIMIT,
      margin_edit_target_order_price: DEFAULT_PRIVATE_RATE_LIMIT,
      margin_add_margin: DEFAULT_PRIVATE_RATE_LIMIT,
      margin_remove_margin: DEFAULT_PRIVATE_RATE_LIMIT,
      user_balances: DEFAULT_PRIVATE_RATE_LIMIT,
      user_info: DEFAULT_PRIVATE_RATE_LIMIT,
      wallets_transfer: DEFAULT_PRIVATE_RATE_LIMIT,
      wallets_sub_account_transfer: DEFAULT_PRIVATE_RATE_LIMIT
    }.freeze

    attr_accessor :api_key, :api_secret, :api_base_url, :public_base_url,
                  :socket_base_url, :socket_io_connect_options, :open_timeout, :read_timeout, :max_retries,
                  :retry_base_interval, :user_agent, :socket_io_backend_factory,
                  :endpoint_rate_limits, :logger, :socket_reconnect_attempts,
                  :socket_reconnect_interval, :socket_heartbeat_interval,
                  :socket_liveness_timeout, :market_data_retry_budget,
                  :private_read_retry_budget, :idempotent_order_retry_budget,
                  :circuit_breaker_threshold, :circuit_breaker_cooldown

    def initialize
      @api_base_url = DEFAULT_API_BASE_URL
      @public_base_url = DEFAULT_PUBLIC_BASE_URL
      @socket_base_url = DEFAULT_SOCKET_BASE_URL
      # CoinDCX stream matches official socket.io-client 2.x (Engine.IO v3). The default backend
      # `socket.io-client-simple` only parses that protocol; `EIO: 4` breaks the handshake/payloads.
      @socket_io_connect_options = { EIO: 3 }
      @open_timeout = 5
      @read_timeout = 30
      @max_retries = 2
      @retry_base_interval = 0.25
      @user_agent = DEFAULT_USER_AGENT
      @endpoint_rate_limits = DEFAULT_ENDPOINT_RATE_LIMITS.transform_values(&:dup)
      @logger = nil
      @socket_reconnect_attempts = 5
      @socket_reconnect_interval = 1.0
      @socket_heartbeat_interval = 10.0
      @socket_liveness_timeout = 60.0
      @market_data_retry_budget = 2
      @private_read_retry_budget = 1
      @idempotent_order_retry_budget = 1
      @circuit_breaker_threshold = 3
      @circuit_breaker_cooldown = 30.0
    end

    def rate_limit_for(bucket_name)
      endpoint_rate_limits[bucket_name.to_sym]
    end
  end
end
