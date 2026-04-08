# frozen_string_literal: true

module CoinDCX
  module WS
    class SocketIOClient
      def initialize(configuration:, backend: nil, sleeper: Kernel)
        @configuration = configuration
        @logger = configuration.logger || Logging::NullLogger.new
        @backend = Contracts::SocketBackend.validate!(backend || build_backend)
        @private_channels = PrivateChannels.new(configuration: configuration)
        @sleeper = sleeper
        @subscriptions = []
        @connection_handler_registered = false
      end

      def connect
        connect_with_retries
        register_connection_handler
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
        register_subscription(type: :public, channel_name: channel_name, event_name: event_name, &block)
      end

      def subscribe_private(event_name:, channel_name: PrivateChannels::DEFAULT_CHANNEL_NAME, &block)
        register_subscription(type: :private, channel_name: channel_name, event_name: event_name, &block)
      end

      private

      attr_reader :configuration, :logger, :private_channels, :sleeper

      def register_subscription(type:, channel_name:, event_name:, &block)
        @subscriptions << { type: type, channel_name: channel_name, event_name: event_name }
        on(event_name, &block) if block_given?
        emit_join(type: type, channel_name: channel_name)
        self
      end

      def connect_with_retries
        attempts = 0

        begin
          attempts += 1
          @backend.connect(configuration.socket_base_url)
        rescue Errors::SocketConnectionError => error
          raise error if attempts > configuration.socket_reconnect_attempts

          sleep_interval = configuration.socket_reconnect_interval * attempts
          logger.warn("Retrying CoinDCX socket connection after #{error.class}: attempt=#{attempts}, sleep=#{sleep_interval}")
          sleeper.sleep(sleep_interval)
          retry
        end
      end

      def register_connection_handler
        return if @connection_handler_registered

        @backend.on(:connect) { resubscribe_all }
        @backend.on(:disconnect) { logger.warn("CoinDCX socket disconnected") }
        @connection_handler_registered = true
      end

      def resubscribe_all
        @subscriptions.each do |subscription|
          emit_join(type: subscription.fetch(:type), channel_name: subscription.fetch(:channel_name))
        end
      end

      def emit_join(type:, channel_name:)
        @backend.emit("join", join_payload(type: type, channel_name: channel_name))
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
