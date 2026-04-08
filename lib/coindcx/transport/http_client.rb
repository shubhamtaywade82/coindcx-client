# frozen_string_literal: true

require "faraday"
require "json"

module CoinDCX
  module Transport
    class HttpClient
      def initialize(configuration:, stubs: nil)
        @configuration = configuration
        @rate_limits = RateLimitRegistry.new(configuration.endpoint_rate_limits)
        @logger = configuration.logger || Logging::NullLogger.new
        @retry_policy = RetryPolicy.new(
          max_retries: configuration.max_retries,
          base_interval: configuration.retry_base_interval,
          logger: @logger
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
        rate_limits.acquire(bucket)
        logger.debug("CoinDCX #{method.upcase} #{base} #{path} bucket=#{bucket.inspect}")

        retry_policy.with_retries(method: method, path: path, base: base) do
          response = connection_for(base).public_send(method, path) do |request|
            request.headers["Accept"] = "application/json"
            request.headers["User-Agent"] = configuration.user_agent
            request.options.timeout = configuration.read_timeout
            request.options.open_timeout = configuration.open_timeout
            apply_payload(request, method: method, params: params, body: body, auth: auth)
          end

          parse_response(response, path)
        end
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
        return parsed_body if status.between?(200, 299)

        logger.error("CoinDCX request failed path=#{path} status=#{status}")
        raise classify_error(status, path, parsed_body)
      end

      def classify_error(status, path, body)
        message = "CoinDCX request failed for #{path}"
        return Errors::AuthError.new(message, status: status, body: body) if status == 401
        return Errors::RateLimitError.new(message, status: status, body: body) if status == 429

        Errors::RequestError.new(message, status: status, body: body)
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
    end
  end
end
