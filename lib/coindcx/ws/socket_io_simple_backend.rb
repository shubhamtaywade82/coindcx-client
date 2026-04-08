# frozen_string_literal: true

require "socket.io-client-simple"

module CoinDCX
  module WS
    class SocketIOSimpleBackend
      def initialize(socket_factory: ::SocketIO::Client::Simple, connect_options: nil)
        @socket_factory = socket_factory
        @connect_options = connect_options || { EIO: 4 }
      end

      # Engine.IO version must match the server (`EIO` query param). CoinDCX commonly expects v4;
      # override via `CoinDCX::Configuration#socket_io_connect_options` (e.g. `{ EIO: 3 }`).
      def connect(url)
        @socket = @socket_factory.connect(url, @connect_options.dup)
      rescue StandardError => e
        raise Errors::SocketConnectionError, e.message
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
