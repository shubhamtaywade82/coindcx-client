# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module CoinDCX
  module Transport
    class HttpClient
      RETRYABLE_ERRORS = [Timeout::Error, Errno::ECONNRESET, Errno::ETIMEDOUT, EOFError].freeze

      def initialize(configuration:)
        @configuration = configuration
        @rate_limits = RateLimitRegistry.new(configuration.endpoint_rate_limits)
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

      attr_reader :rate_limits

      def request(method, path, params:, body:, auth:, base:, bucket:)
        rate_limits.acquire(bucket)
        attempts = 0

        begin
          attempts += 1
          uri = build_uri(path, params, base)
          response = build_http(uri).request(build_request(method, uri, body, auth))
          parse_response(response, path)
        rescue *RETRYABLE_ERRORS => error
          raise error if attempts > configuration.max_retries

          sleep(configuration.retry_delay * attempts)
          retry
        end
      end

      def build_uri(path, params, base)
        uri = URI.join(base_url_for(base), path)
        query_pairs = URI.decode_www_form(uri.query.to_s) + encode_query(params)
        uri.query = query_pairs.empty? ? nil : URI.encode_www_form(query_pairs)
        uri
      end

      def build_http(uri)
        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: configuration.open_timeout,
          read_timeout: configuration.read_timeout
        )
      end

      def build_request(method, uri, body, auth)
        request_class = { get: Net::HTTP::Get, post: Net::HTTP::Post, delete: Net::HTTP::Delete }.fetch(method)
        request = request_class.new(uri)
        request["Accept"] = "application/json"
        request["User-Agent"] = configuration.user_agent

        return attach_authenticated_body(request, body) if auth
        return request if method == :get || body.empty?

        request["Content-Type"] = "application/json"
        request.body = JSON.generate(Utils::Payload.stringify_keys(Utils::Payload.compact_hash(body)))
        request
      end

      def attach_authenticated_body(request, body)
        signer = Auth::Signer.new(api_key: fetch_api_key, api_secret: fetch_api_secret)
        normalized_body, headers = signer.authenticated_request(body)
        request["Content-Type"] = "application/json"
        headers.each { |header_name, value| request[header_name] = value }
        request.body = JSON.generate(Utils::Payload.stringify_keys(normalized_body))
        request
      end

      def parse_response(response, path)
        parsed_body = parse_body(response.body)
        return parsed_body if response.code.to_i.between?(200, 299)

        error_class = response.code.to_i == 401 ? Errors::AuthenticationError : Errors::RequestError
        raise error_class.new("CoinDCX request failed for #{path}", status: response.code.to_i, body: parsed_body)
      end

      def parse_body(body)
        return {} if body.nil? || body.strip.empty?

        JSON.parse(body)
      rescue JSON::ParserError
        body
      end

      def encode_query(params)
        Utils::Payload.compact_hash(params).each_with_object([]) do |(key, value), pairs|
          if value.is_a?(Array)
            value.each { |member| pairs << [key.to_s, member] }
          else
            pairs << [key.to_s, value]
          end
        end
      end

      def base_url_for(base)
        return configuration.api_base_url if base == :api
        return configuration.public_base_url if base == :public

        raise Errors::ConfigurationError, "unknown base url: #{base.inspect}"
      end

      def fetch_api_key
        return configuration.api_key if configuration.api_key

        raise Errors::AuthenticationError, "api_key is required for authenticated endpoints"
      end

      def fetch_api_secret
        return configuration.api_secret if configuration.api_secret

        raise Errors::AuthenticationError, "api_secret is required for authenticated endpoints"
      end
    end
  end
end
