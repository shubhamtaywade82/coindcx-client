# frozen_string_literal: true

module CoinDCX
  module Errors
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class ValidationError < Error; end
    class MissingDependencyError < Error; end
    class SocketError < Error; end
    class RateLimitError < Error; end

    class AuthenticationError < Error
      attr_reader :status, :body

      def initialize(message = "CoinDCX authentication failed", status: nil, body: nil)
        super(message)
        @status = status
        @body = body
      end
    end

    class RequestError < Error
      attr_reader :status, :body

      def initialize(message, status: nil, body: nil)
        super(message)
        @status = status
        @body = body
      end
    end
  end
end
