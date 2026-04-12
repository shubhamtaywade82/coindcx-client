# frozen_string_literal: true

module CoinDCX
  module Transport
    class RequestPolicy
      RETRYABLE_STATUSES = [500, 502, 503, 504].freeze
      VALIDATION_STATUSES = [400, 404, 422].freeze
      ORDER_CREATE_PATHS = [
        "/exchange/v1/orders/create", "/exchange/v1/orders/create_multiple",
        "/exchange/v1/derivatives/futures/orders/create", "/exchange/v1/margin/create"
      ].freeze
      CRITICAL_ORDER_PATHS = ORDER_CREATE_PATHS.freeze
      # Authenticated GETs that mirror private read semantics (signed body + X-AUTH headers).
      FUTURES_AUTH_GET_READ_PATHS = ["/exchange/v1/derivatives/futures/data/instrument"].freeze

      READ_ONLY_POST_PATHS = [
        "/exchange/v1/orders/status", "/exchange/v1/orders/status_multiple",
        "/exchange/v1/orders/active_orders", "/exchange/v1/orders/active_orders_count",
        "/exchange/v1/orders/trade_history", "/exchange/v1/margin/fetch_orders",
        "/exchange/v1/margin/order", "/exchange/v1/users/balances",
        "/exchange/v1/users/info", "/exchange/v1/derivatives/futures/orders",
        "/exchange/v1/derivatives/futures/trades", "/exchange/v1/derivatives/futures/positions",
        "/exchange/v1/derivatives/futures/positions/transactions",
        "/exchange/v1/derivatives/futures/positions/cross_margin_details",
        "/exchange/v1/derivatives/futures/wallets", "/exchange/v1/funding/fetch_orders"
      ].freeze
      IDEMPOTENCY_KEYS = %w[client_order_id clientOrderId].freeze

      def self.build(configuration:, method:, path:, body:, auth:, bucket:)
        new(
          operation_name: operation_name_for(method: method, path: path),
          retry_budget: retry_budget_for(configuration: configuration, method: method, path: path, body: body, auth: auth),
          circuit_breaker_key: circuit_breaker_key_for(path: path),
          retry_rate_limits: retry_rate_limits_for?(method: method, path: path),
          requires_idempotency: ORDER_CREATE_PATHS.include?(path),
          idempotency_satisfied: idempotency_contract_met?(path: path, body: body),
          bucket: bucket
        )
      end

      def self.operation_name_for(method:, path:)
        normalized_path = path.gsub(%r{\A/+}, "").tr("/", "_")
        "#{method}_#{normalized_path}"
      end

      def self.retry_budget_for(configuration:, method:, path:, body:, auth:)
        return configuration.market_data_retry_budget if method == :get && !auth
        return configuration.private_read_retry_budget if futures_signed_read_get?(method, path, auth)
        return configuration.private_read_retry_budget if READ_ONLY_POST_PATHS.include?(path)
        return configuration.idempotent_order_retry_budget if idempotent_order_retry?(path, body)

        0
      end

      def self.futures_signed_read_get?(method, path, auth)
        method == :get && auth && FUTURES_AUTH_GET_READ_PATHS.include?(path)
      end

      def self.idempotent_order_retry?(path, body)
        ORDER_CREATE_PATHS.include?(path) && idempotency_contract_met?(path: path, body: body)
      end

      def self.circuit_breaker_key_for(path:)
        return path if CRITICAL_ORDER_PATHS.include?(path)

        nil
      end

      def self.retry_rate_limits_for?(method:, path:)
        method == :get || READ_ONLY_POST_PATHS.include?(path)
      end

      def self.idempotency_key_present?(body)
        case body
        when Hash
          body.any? do |key, value|
            IDEMPOTENCY_KEYS.include?(key.to_s) || idempotency_key_present?(value)
          end
        when Array
          body.any? { |value| idempotency_key_present?(value) }
        else
          false
        end
      end

      def self.idempotency_contract_met?(path:, body:)
        return false unless ORDER_CREATE_PATHS.include?(path)

        if path == "/exchange/v1/orders/create_multiple"
          orders = extract_orders(body)
          return false if orders.empty?

          return orders.all? { |order| idempotency_key_present?(order) }
        end

        idempotency_key_present?(body)
      end

      def self.extract_orders(body)
        return [] unless body.is_a?(Hash)

        body[:orders] || body["orders"] || []
      end

      def initialize(operation_name:, retry_budget:, circuit_breaker_key:, retry_rate_limits:, requires_idempotency:,
                     idempotency_satisfied:, bucket:)
        @operation_name = operation_name
        @retry_budget = retry_budget
        @circuit_breaker_key = circuit_breaker_key
        @retry_rate_limits = retry_rate_limits
        @requires_idempotency = requires_idempotency
        @idempotency_satisfied = idempotency_satisfied
        @bucket = bucket
      end

      attr_reader :operation_name, :retry_budget, :circuit_breaker_key, :bucket

      def retryable_transport_error?
        retry_budget.positive?
      end

      def retryable_response?(status:, headers:)
        return true if RETRYABLE_STATUSES.include?(status) && retry_budget.positive?
        return false unless status == 429 && retry_budget.positive? && @retry_rate_limits

        retry_after(headers).to_f.positive?
      end

      def retry_after(headers)
        return nil unless headers.respond_to?(:[])

        headers["Retry-After"] || headers["retry-after"]
      end

      def validation_status?(status)
        VALIDATION_STATUSES.include?(status)
      end

      def critical_order?
        !circuit_breaker_key.nil?
      end

      def requires_idempotency?
        @requires_idempotency
      end

      def idempotency_satisfied?
        @idempotency_satisfied
      end
    end
  end
end
