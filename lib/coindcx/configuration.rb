# frozen_string_literal: true

module CoinDCX
  class Configuration
    DEFAULT_API_BASE_URL = "https://api.coindcx.com"
    DEFAULT_PUBLIC_BASE_URL = "https://public.coindcx.com"
    DEFAULT_SOCKET_BASE_URL = "wss://stream.coindcx.com"
    DEFAULT_USER_AGENT = "coindcx-client/#{VERSION}"
    DEFAULT_ENDPOINT_RATE_LIMITS = {
      spot_create_order_multiple: { limit: 2000, period: 60 },
      spot_create_order: { limit: 2000, period: 60 },
      spot_cancel_all: { limit: 30, period: 60 },
      spot_order_status_multiple: { limit: 2000, period: 60 },
      spot_order_status: { limit: 2000, period: 60 },
      spot_cancel_multiple_by_id: { limit: 300, period: 60 },
      spot_cancel_order: { limit: 2000, period: 60 },
      spot_active_order: { limit: 300, period: 60 },
      spot_edit_price: { limit: 2000, period: 60 }
    }.freeze

    attr_accessor :api_key, :api_secret, :api_base_url, :public_base_url,
                  :socket_base_url, :open_timeout, :read_timeout, :max_retries,
                  :retry_base_interval, :user_agent, :socket_io_backend_factory,
                  :endpoint_rate_limits, :logger, :socket_reconnect_attempts,
                  :socket_reconnect_interval

    def initialize
      @api_base_url = DEFAULT_API_BASE_URL
      @public_base_url = DEFAULT_PUBLIC_BASE_URL
      @socket_base_url = DEFAULT_SOCKET_BASE_URL
      @open_timeout = 5
      @read_timeout = 30
      @max_retries = 2
      @retry_base_interval = 0.25
      @user_agent = DEFAULT_USER_AGENT
      @endpoint_rate_limits = DEFAULT_ENDPOINT_RATE_LIMITS.transform_values(&:dup)
      @logger = nil
      @socket_reconnect_attempts = 3
      @socket_reconnect_interval = 1.0
    end

    def rate_limit_for(bucket_name)
      endpoint_rate_limits[bucket_name.to_sym]
    end
  end
end
