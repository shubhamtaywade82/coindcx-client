# frozen_string_literal: true

module CoinDCX
  module Errors
    class Error < StandardError
      attr_reader :category, :code, :request_context, :retryable

      def initialize(message, category: nil, code: nil, request_context: nil, retryable: false)
        super(message)
        @category = category
        @code = code
        @request_context = request_context
        @retryable = retryable
      end
    end

    class ConfigurationError < Error; end
    class ValidationError < Error; end
    class MissingDependencyError < Error; end

    class SocketError < Error; end
    class SocketConnectionError < SocketError; end
    class SocketAuthenticationError < SocketError; end
    class SocketStateError < SocketError; end
    class SocketHeartbeatTimeoutError < SocketError; end

    class ApiError < Error
      attr_reader :status, :body, :retry_after

      def initialize(message, status: nil, body: nil, category: nil, code: nil, request_context: nil, retryable: false, retry_after: nil)
        super(message, category: category, code: code, request_context: request_context, retryable: retryable)
        @status = status
        @body = body
        @retry_after = retry_after
      end
    end

    class RequestError < ApiError; end
    class RateLimitError < ApiError; end
    class AuthError < ApiError; end
    class RemoteValidationError < RequestError; end
    class TransportError < RequestError; end
    class UpstreamServerError < RequestError; end
    class RetryableRateLimitError < RateLimitError; end
    class CircuitOpenError < RequestError; end

    AuthenticationError = AuthError
  end
end
