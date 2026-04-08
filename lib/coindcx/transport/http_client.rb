# frozen_string_literal: true

require "faraday"
require "json"
require "securerandom"

module CoinDCX
  module Transport
    class HttpClient
      READ_ONLY_POST_PATHS = [
        "/exchange/v1/orders/status",
        "/exchange/v1/orders/status_multiple",
        "/exchange/v1/orders/active_orders",
        "/exchange/v1/orders/active_orders_count",
        "/exchange/v1/orders/trade_history",
        "/exchange/v1/margin/fetch_orders",
        "/exchange/v1/margin/order",
        "/exchange/v1/users/balances",
        "/exchange/v1/users/info",
        "/exchange/v1/derivatives/futures/orders",
        "/exchange/v1/derivatives/futures/positions",
        "/exchange/v1/derivatives/futures/positions/transactions",
        "/exchange/v1/derivatives/futures/positions/cross_margin_details",
        "/exchange/v1/derivatives/futures/wallets"
      ].freeze

      NON_IDEMPOTENT_ORDER_PATHS = [
        "/exchange/v1/orders/create",
        "/exchange/v1/orders/create_multiple",
        "/exchange/v1/derivatives/futures/orders/create",
        "/exchange/v1/margin/create"
      ].freeze

      IDEMPOTENCY_KEYS = %w[client_order_id clientOrderId].freeze

      def initialize(configuration:, stubs: nil, sleeper: Kernel)
        @configuration = configuration
        @rate_limits = RateLimitRegistry.new(configuration.endpoint_rate_limits)
        @logger = configuration.logger || Logging::NullLogger.new
        @retry_policy = RetryPolicy.new(
          max_retries: configuration.max_retries,
          base_interval: configuration.retry_base_interval,
          logger: @logger,
          sleeper: sleeper
        )
        @connections = {
          api: build_connection(configuration.api_base_url, stubs),
          public: build_connection(configuration.public_base_url, stubs)
        }
      end

      attr_reader :configuration

      def get(path, params: {}, auth: false, base: :api, bucket: nil)
        request(:get, path, params: params, body: {}, auth: auth, base: base, bucket: bucket)
      end

      def post(path, body: {}, auth: false, base: :api, bucket: nil)
        request(:post, path, params: {}, body: body, auth: auth, base: base, bucket: bucket)
      end

      def delete(path, body: {}, auth: false, base: :api, bucket: nil)
        request(:delete, path, params: {}, body: body, auth: auth, base: base, bucket: bucket)
      end

      private

      attr_reader :logger, :rate_limits, :retry_policy

      def request(method, path, params:, body:, auth:, base:, bucket:)
        request_id = SecureRandom.uuid
        started_at = monotonic_time
        retries = 0

        rate_limits.throttle(bucket, required: !bucket.nil?)

        normalized_response = retry_policy.with_retries(
          request_context(method: method, path: path, base: base, request_id: request_id),
          retryable: retryable_request?(method: method, path: path, body: body)
        ) do |attempts|
          retries = attempts - 1
          response = connection_for(base).public_send(method, path) do |request|
            request.headers["Accept"] = "application/json"
            request.headers["User-Agent"] = configuration.user_agent
            request.options.timeout = configuration.read_timeout
            request.options.open_timeout = configuration.open_timeout
            apply_payload(request, method: method, params: params, body: body, auth: auth)
          end

          parse_response(response, path)
        end

        log(:info, event: "api_call", endpoint: path, request_id: request_id, latency: elapsed_since(started_at), retries: retries)
        normalized_response.fetch(:data)
      rescue Errors::ApiError => e
        log(
          :error,
          event: "api_call_failed",
          endpoint: path,
          request_id: request_id,
          latency: elapsed_since(started_at),
          retries: retries,
          error_code: normalized_error_code(e.body),
          error_message: normalized_error_message(e.body)
        )
        raise
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
        log(
          :error,
          event: "api_transport_failed",
          endpoint: path,
          request_id: request_id,
          latency: elapsed_since(started_at),
          retries: retries,
          error_code: e.class.name,
          error_message: e.message
        )
        raise
      end

      def apply_payload(request, method:, params:, body:, auth:)
        request.params.update(encode_query(params)) unless params.empty?
        return if method == :get && !auth

        normalized_body = auth ? authenticated_body(request, body) : plain_body(request, body)
        request.body = JSON.generate(Utils::Payload.stringify_keys(normalized_body)) unless normalized_body.empty?
      end

      def authenticated_body(request, body)
        signer = Auth::Signer.new(api_key: fetch_api_key, api_secret: fetch_api_secret)
        normalized_body, headers = signer.authenticated_request(body)
        request.headers["Content-Type"] = "application/json"
        headers.each { |header_name, value| request.headers[header_name] = value }
        normalized_body
      end

      def plain_body(request, body)
        normalized_body = Utils::Payload.compact_hash(body)
        request.headers["Content-Type"] = "application/json"
        normalized_body
      end

      def parse_response(response, path)
        parsed_body = parse_body(response.body)
        status = response.status.to_i
        return ResponseNormalizer.success(parsed_body) if status.between?(200, 299)

        raise classify_error(status, path, parsed_body)
      end

      def classify_error(status, path, body)
        message = "CoinDCX request failed for #{path}"
        normalized_body = ResponseNormalizer.failure(status: status, body: body, fallback_message: message)
        return Errors::AuthError.new(message, status: status, body: normalized_body) if status == 401
        return Errors::RateLimitError.new(message, status: status, body: normalized_body) if status == 429

        Errors::RequestError.new(message, status: status, body: normalized_body)
      end

      def parse_body(body)
        return {} if body.nil? || body.strip.empty?

        JSON.parse(body)
      rescue JSON::ParserError
        body
      end

      def encode_query(params)
        Utils::Payload.compact_hash(params).each_with_object({}) do |(key, value), result|
          result[key.to_s] = value
        end
      end

      def retryable_request?(method:, path:, body:)
        return true if method == :get || method == :delete
        return true if READ_ONLY_POST_PATHS.include?(path)
        return true if NON_IDEMPOTENT_ORDER_PATHS.include?(path) && idempotency_key_present?(body)

        false
      end

      def idempotency_key_present?(body)
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

      def request_context(method:, path:, base:, request_id:)
        {
          endpoint: path,
          request_id: request_id,
          method: method.to_s.upcase,
          base: base
        }
      end

      def normalized_error_code(body)
        return nil unless body.respond_to?(:dig)

        body.dig(:error, :code)
      end

      def normalized_error_message(body)
        return body.message if body.is_a?(StandardError)
        return body.to_s unless body.respond_to?(:dig)

        body.dig(:error, :message)
      end

      def connection_for(base)
        @connections.fetch(base) do
          raise Errors::ConfigurationError, "unknown base url: #{base.inspect}"
        end
      end

      def build_connection(base_url, stubs)
        Faraday.new(url: base_url) do |connection|
          connection.request :url_encoded
          connection.adapter(stubs ? :test : Faraday.default_adapter, stubs)
        end
      end

      def fetch_api_key
        return configuration.api_key if configuration.api_key

        raise Errors::AuthError, "api_key is required for authenticated endpoints"
      end

      def fetch_api_secret
        return configuration.api_secret if configuration.api_secret

        raise Errors::AuthError, "api_secret is required for authenticated endpoints"
      end

      def elapsed_since(started_at)
        monotonic_time - started_at
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def log(level, payload)
        Logging::StructuredLogger.log(logger, level, payload)
      end
    end
  end
end
