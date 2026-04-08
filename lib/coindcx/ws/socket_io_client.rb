# frozen_string_literal: true

module CoinDCX
  module WS
    class SocketIOClient
      def initialize(configuration:, backend: nil)
        @configuration = configuration
        @backend = Contracts::SocketBackend.validate!(backend || build_backend)
        @private_channels = PrivateChannels.new(configuration: configuration)
      end

      def connect
        @backend.connect(configuration.socket_base_url)
        self
      end

      def disconnect
        @backend.disconnect
      end

      def on(event_name, &block)
        @backend.on(event_name, &block)
        self
      end

      def subscribe_public(channel_name:, event_name:, &block)
        subscribe(join_payload: { "channelName" => Contracts::ChannelName.validate!(channel_name) }, event_name: event_name, &block)
      end

      def subscribe_private(event_name:, channel_name: PrivateChannels::DEFAULT_CHANNEL_NAME, &block)
        subscribe(join_payload: @private_channels.join_payload(channel_name: channel_name), event_name: event_name, &block)
      end

      private

      attr_reader :configuration

      def subscribe(join_payload:, event_name:)
        on(event_name) { |payload| yield(payload) } if block_given?
        @backend.emit("join", join_payload)
        self
      end

      def build_backend
        factory = configuration.socket_io_backend_factory
        return factory.call if factory

        raise Errors::MissingDependencyError,
              "configure socket_io_backend_factory with a Socket.io backend; CoinDCX sockets are not generic WebSockets"
      end
    end
  end
end
