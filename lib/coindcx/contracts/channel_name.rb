# frozen_string_literal: true

module CoinDCX
  module Contracts
    module ChannelName
      module_function

      def validate!(channel_name)
        normalized_channel_name = channel_name.to_s.strip
        raise Errors::ValidationError, "channel_name must be provided" if normalized_channel_name.empty?
        return normalized_channel_name if valid_format?(normalized_channel_name)

        raise Errors::ValidationError, "channel_name must match a CoinDCX channel name"
      end

      def valid_format?(channel_name)
        channel_name == "coindcx" ||
          channel_name.include?("@") ||
          channel_name.include?("_")
      end
    end
  end
end
