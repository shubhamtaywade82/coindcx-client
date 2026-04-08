# frozen_string_literal: true

require_relative "uri_ruby3_compat"
require "socket.io-client-simple"

module CoinDCX
  module WS
    class SocketIOSimpleBackend
      def initialize(socket_client_class: ::SocketIO::Client::Simple::Client, connect_options: nil)
        @socket_client_class = socket_client_class
        @connect_options = connect_options || { EIO: 3 }
      end

      # Engine.IO version must match the server (`EIO` query param). CoinDCX stream uses Engine.IO v3
      # (same as socket.io-client 2.3.x in their docs). This gem's default backend only supports v3;
      # use `socket_io_backend_factory` if you need a different stack.
      #
      # Two-step setup so ConnectionManager can register Socket.IO listeners before the WebSocket
      # opens; otherwise the Engine.IO "open" packet can fire :connect before we listen, and join
      # emits run while the client still rejects emit (pre-handshake).
      def connect(url)
        disconnect
        @socket = @socket_client_class.new(url, @connect_options.dup)
        self
      rescue StandardError => e
        @socket = nil
        raise Errors::SocketConnectionError, e.message
      end

      def start_transport!
        raise Errors::SocketError, "socket client missing before start_transport!" if @socket.nil?

        @socket.connect
        self
      end

      def emit(event_name, payload)
        socket.emit(event_name, payload)
      end

      def on(event_name, &block)
        socket.on(event_name, &block)
      end

      def disconnect
        return if @socket.nil?

        if @socket.respond_to?(:disconnect)
          @socket.disconnect
        elsif @socket.respond_to?(:close)
          @socket.close
        end
        @socket = nil
      end

      private

      def socket
        @socket || raise(Errors::SocketError, "socket connection has not been established")
      end
    end
  end
end
