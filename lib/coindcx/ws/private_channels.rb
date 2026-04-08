# frozen_string_literal: true

module CoinDCX
  module WS
    class PrivateChannels
      DEFAULT_CHANNEL_NAME = "coindcx"
      BALANCE_UPDATE_EVENT = "balance-update"
      ORDER_UPDATE_EVENT = "order-update"
      TRADE_UPDATE_EVENT = "trade-update"

      def initialize(configuration:)
        @configuration = configuration
      end

      def join_payload(channel_name: DEFAULT_CHANNEL_NAME)
        signer.private_channel_join(channel_name: channel_name)
      end

      private

      attr_reader :configuration

      def signer
        @signer ||= Auth::Signer.new(
          api_key: configuration.api_key || missing_configuration!(:api_key),
          api_secret: configuration.api_secret || missing_configuration!(:api_secret)
        )
      end

      def missing_configuration!(setting_name)
        raise Errors::AuthenticationError, "#{setting_name} is required for private websocket subscriptions"
      end
    end
  end
end
