# frozen_string_literal: true

module CoinDCX
  module WS
    class SocketIOClient
      def initialize(configuration:, backend: nil, sleeper: Kernel, thread_factory: nil, monotonic_clock: nil)
        @configuration = configuration
        @logger = configuration.logger || Logging::NullLogger.new
        @backend = Contracts::SocketBackend.validate!(backend || build_backend)
        @private_channels = PrivateChannels.new(configuration: configuration)
        @connection_manager = ConnectionManager.new(
          configuration: configuration,
          backend: @backend,
          logger: @logger,
          sleeper: sleeper,
          thread_factory: thread_factory,
          monotonic_clock: monotonic_clock
        )
      end

      def connect
        connection_manager.connect
        self
      end

      def disconnect
        connection_manager.disconnect
        self
      end

      def on(event_name, &block)
        connection_manager.on(event_name, &block)
        self
      end

      def subscribe_public(channel_name:, event_name:, &block)
        register_subscription(type: :public, channel_name: channel_name, event_name: event_name, &block)
      end

      def subscribe_private(event_name:, channel_name: PrivateChannels::DEFAULT_CHANNEL_NAME, &block)
        register_subscription(type: :private, channel_name: channel_name, event_name: event_name, &block)
      end

      def alive?
        connection_manager.alive?
      end

      private

      attr_reader :configuration, :backend, :private_channels, :connection_manager

      def register_subscription(type:, channel_name:, event_name:, &block)
        on(event_name, &block) if block_given?
        connection_manager.subscribe(
          type: type,
          channel_name: channel_name,
          event_name: event_name,
          payload_builder: -> { join_payload(type: type, channel_name: channel_name) },
          delivery_mode: :at_least_once
        )
        self
      end

      def join_payload(type:, channel_name:)
        return { "channelName" => Contracts::ChannelName.validate!(channel_name) } if type == :public

        private_channels.join_payload(channel_name: channel_name)
      end

      def build_backend
        factory = configuration.socket_io_backend_factory
        return Contracts::SocketBackend.validate!(factory.call) if factory

        SocketIOSimpleBackend.new
      end
    end
  end
end
