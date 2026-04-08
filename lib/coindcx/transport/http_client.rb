# frozen_string_literal: true

require "faraday"
require "json"
require "securerandom"

module CoinDCX
  module Transport
    class HttpClient
      def initialize(configuration:, stubs: nil, sleeper: Kernel, monotonic_clock: nil)
        @configuration = configuration
        @rate_limits = RateLimitRegistry.new(configuration.endpoint_rate_limits)
        @logger = configuration.logger || Logging::NullLogger.new
        @retry_policy = RetryPolicy.new(
          max_retries: configuration.max_retries,
          base_interval: configuration.retry_base_interval,
          logger: @logger,
          sleeper: sleeper
        )
        @circuit_breaker = CircuitBreaker.new(
          threshold: configuration.circuit_breaker_threshold,
          cooldown: configuration.circuit_breaker_cooldown,
          monotonic_clock: monotonic_clock
        )
        @connections = {
          api: build_connection(configuration.api_base_url, stubs),
          public: build_connection(configuration.public_base_url, stubs)
        }
      end

      attr_reader :configuration

      def get(path, params: {}, body: {}, auth: false, base: :api, bucket: nil)
        request(:get, path, params: params, body: body, auth: auth, base: base, bucket: bucket)
      end

      def post(path, body: {}, auth: false, base: :api, bucket: nil)
        request(:post, path, params: {}, body: body, auth: auth, base: base, bucket: bucket)
      end

      def delete(path, body: {}, auth: false, base: :api, bucket: nil)
        request(:delete, path, params: {}, body: body, auth: auth, base: base, bucket: bucket)
      end

      private

      attr_reader :logger, :rate_limits, :retry_policy, :circuit_breaker

      def request(method, path, params:, body:, auth:, base:, bucket:)
        policy = RequestPolicy.build(
          configuration: configuration,
          method: method,
          path: path,
          body: body,
          auth: auth,
          bucket: bucket
        )
        request_id = SecureRandom.uuid
        started_at = monotonic_time
        retries = 0
        response_status = nil
        context = request_context(
          method: method,
          path: path,
          base: base,
          request_id: request_id,
          operation_name: policy.operation_name
        )

        rate_limits.throttle(policy.bucket, required: auth)

        normalized_response = circuit_breaker.guard(policy.circuit_breaker_key, request_context: context) do
          retry_policy.with_retries(context, policy: policy) do |attempts|
            retries = attempts - 1
            response = connection_for(base).public_send(method, path) do |request|
              request.headers["Accept"] = "application/json"
              request.headers["User-Agent"] = configuration.user_agent
              request.options.timeout = configuration.read_timeout
              request.options.open_timeout = configuration.open_timeout
              apply_payload(request, method: method, params: params, body: body, auth: auth)
            end

            response_status = response.status.to_i
            parse_response(
              response,
              path,
              request_context: context,
              policy: policy
            )
          end
        end

        log(
          :info,
          event: "api_call",
          endpoint: path,
          operation: policy.operation_name,
          request_id: request_id,
          latency: elapsed_since(started_at),
          retries: retries,
          response_status: response_status
        )
        normalized_response.fetch(:data)
      rescue Errors::ApiError => e
        log(
          :error,
          event: "api_call_failed",
          endpoint: path,
          operation: policy.operation_name,
          request_id: request_id,
          latency: elapsed_since(started_at),
          retries: retries,
          response_status: e.status,
          category: e.category,
          error_code: normalized_error_code(e.body),
          error_message: normalized_error_message(e.body)
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

      def parse_response(response, path, request_context:, policy:)
        parsed_body = parse_body(response.body)
        status = response.status.to_i
        return ResponseNormalizer.success(parsed_body) if status.between?(200, 299)

        raise classify_error(
          status,
          path,
          parsed_body,
          headers: response.headers,
          request_context: request_context,
          policy: policy
        )
      end

      def classify_error(status, path, body, headers:, request_context:, policy:)
        message = "CoinDCX request failed for #{path}"
        error_class, category, retryable = error_details_for(status: status, headers: headers, policy: policy)
        normalized_body = ResponseNormalizer.failure(
          status: status,
          body: body,
          fallback_message: message,
          category: category,
          request_context: request_context,
          retryable: retryable
        )
        error_class.new(
          message,
          status: status,
          body: normalized_body,
          category: category,
          code: normalized_body.dig(:error, :code),
          request_context: request_context,
          retryable: retryable,
          retry_after: policy.retry_after(headers)
        )
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

      def request_context(method:, path:, base:, request_id:, operation_name:)
        {
          endpoint: path,
          request_id: request_id,
          method: method.to_s.upcase,
          base: base,
          operation: operation_name
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

      def error_details_for(status:, headers:, policy:)
        return [Errors::AuthError, :auth, false] if status == 401
        return [Errors::RetryableRateLimitError, :rate_limit, true] if status == 429 && policy.retryable_response?(status: status, headers: headers)
        return [Errors::RateLimitError, :rate_limit, false] if status == 429
        return [Errors::UpstreamServerError, :upstream, policy.retryable_response?(status: status, headers: headers)] if status >= 500
        return [Errors::RemoteValidationError, :validation, false] if policy.validation_status?(status)

        [Errors::RequestError, :request, false]
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
