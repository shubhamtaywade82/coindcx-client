# frozen_string_literal: true

module CoinDCX
  module WS
    module PublicChannels
      VALID_SPOT_ORDER_BOOK_DEPTHS = [20, 50].freeze

      module_function

      def candlestick(pair:, interval:)
        "#{pair}_#{interval}"
      end

      def order_book(pair:, depth: 20)
        return "#{pair}@orderbook@#{depth}" if VALID_SPOT_ORDER_BOOK_DEPTHS.include?(depth)

        raise Errors::ValidationError,
              "spot order book updates are snapshot-based and only documented for depths #{VALID_SPOT_ORDER_BOOK_DEPTHS.join(', ')}"
      end

      def price_stats(pair:)
        "#{pair}@prices"
      end

      def ltp(pair:)
        price_stats(pair: pair)
      end

      def new_trade(pair:)
        "#{pair}@trades"
      end

      def futures_price_stats(instrument:)
        "#{instrument}@prices-futures"
      end

      def futures_ltp(instrument:)
        futures_price_stats(instrument: instrument)
      end

      def futures_new_trade(instrument:)
        "#{instrument}@trades-futures"
      end
    end
  end
end
