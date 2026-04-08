# frozen_string_literal: true

module CoinDCX
  module WS
    module Parsers
      class OrderBookSnapshot
        MAXIMUM_RECENT_ORDERS = 50

        def self.parse(payload)
          new(payload).to_h
        end

        def initialize(payload)
          @payload = Utils::Payload.symbolize_keys(payload || {})
        end

        def to_h
          {
            source: :snapshot,
            maximum_recent_orders: MAXIMUM_RECENT_ORDERS,
            timestamp: payload[:E] || payload[:ts] || payload[:timestamp],
            version: payload[:vs],
            bids: levels_for(payload[:bids]),
            asks: levels_for(payload[:asks])
          }.compact
        end

        private

        attr_reader :payload

        def levels_for(levels)
          return [] unless levels.is_a?(Hash)

          levels.map do |price, quantity|
            { price: price.to_s, quantity: quantity.to_s }
          end
        end
      end
    end
  end
end
