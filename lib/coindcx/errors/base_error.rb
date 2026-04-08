# frozen_string_literal: true

module CoinDCX
  module Errors
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class ValidationError < Error; end
    class MissingDependencyError < Error; end
    class SocketError < Error; end

    class ApiError < Error
      attr_reader :status, :body

      def initialize(message, status: nil, body: nil)
        super(message)
        @status = status
        @body = body
      end
    end

    class RequestError < ApiError; end
    class RateLimitError < ApiError; end
    class AuthError < ApiError; end
    class SocketConnectionError < SocketError; end

    AuthenticationError = AuthError
  end
end
