# frozen_string_literal: true

require "socket.io-client-simple"

module CoinDCX
  module WS
    class SocketIOSimpleBackend
      def initialize(socket_factory: ::SocketIO::Client::Simple)
        @socket_factory = socket_factory
      end

      def connect(url)
        @socket = @socket_factory.connect(url)
      rescue StandardError => error
        raise Errors::SocketConnectionError, error.message
      end

      def emit(event_name, payload)
        socket.emit(event_name, payload)
      end

      def on(event_name, &block)
        socket.on(event_name, &block)
      end

      def disconnect
        socket.close if socket.respond_to?(:close)
      end

      private

      def socket
        @socket || raise(Errors::SocketError, "socket connection has not been established")
      end
    end
  end
end
