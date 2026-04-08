# frozen_string_literal: true

module CoinDCX
  module Contracts
    module ChannelName
      module_function

      def validate!(channel_name)
        return channel_name unless channel_name.to_s.strip.empty?

        raise Errors::ValidationError, "channel_name must be provided"
      end
    end
  end
end
