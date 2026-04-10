# frozen_string_literal: true

module CoinDCX
  module WS
    module PublicChannels
      VALID_SPOT_ORDER_BOOK_DEPTHS = [10, 20, 50].freeze
      VALID_FUTURES_ORDER_BOOK_DEPTHS = VALID_SPOT_ORDER_BOOK_DEPTHS
      VALID_CURRENT_PRICES_SPOT_INTERVALS = %w[1s 10s].freeze
      CURRENT_PRICES_SPOT_UPDATE_EVENT = "currentPrices@spot#update"
      CURRENT_PRICES_FUTURES_CHANNEL = "currentPrices@futures@rt"
      CURRENT_PRICES_FUTURES_UPDATE_EVENT = "currentPrices@futures#update"
      PRICE_STATS_SPOT_UPDATE_EVENT = "priceStats@spot#update"
      CANDLESTICK_EVENT = "candlestick"
      DEPTH_SNAPSHOT_EVENT = "depth-snapshot"
      DEPTH_UPDATE_EVENT = "depth-update"
      NEW_TRADE_EVENT = "new-trade"
      PRICE_CHANGE_EVENT = "price-change"

      module_function

      def candlestick(pair:, interval:)
        "#{Contracts::Identifiers.validate_pair!(pair)}_#{interval}"
      end

      def order_book(pair:, depth: 20)
        return "#{Contracts::Identifiers.validate_pair!(pair)}@orderbook@#{depth}" if VALID_SPOT_ORDER_BOOK_DEPTHS.include?(depth)

        raise Errors::ValidationError,
              "spot order book updates are snapshot-based and only documented for depths #{VALID_SPOT_ORDER_BOOK_DEPTHS.sort.join(', ')}"
      end

      def current_prices_spot(interval:)
        key = interval.to_s.strip
        unless VALID_CURRENT_PRICES_SPOT_INTERVALS.include?(key)
          raise Errors::ValidationError,
                "currentPrices@spot intervals must be one of #{VALID_CURRENT_PRICES_SPOT_INTERVALS.join(', ')}"
        end

        "currentPrices@spot@#{key}"
      end

      def price_stats_spot
        "priceStats@spot@60s"
      end

      def price_stats(pair:)
        "#{Contracts::Identifiers.validate_pair!(pair)}@prices"
      end

      def ltp(pair:)
        price_stats(pair: pair)
      end

      def new_trade(pair:)
        "#{Contracts::Identifiers.validate_pair!(pair)}@trades"
      end

      def futures_candlestick(instrument:, interval:)
        ins = Contracts::Identifiers.validate_instrument!(instrument)
        iv = interval.to_s.strip
        raise Errors::ValidationError, "futures candlestick interval must be non-empty" if iv.empty?

        "#{ins}_#{iv}-futures"
      end

      def futures_order_book(instrument:, depth: 20)
        ins = Contracts::Identifiers.validate_instrument!(instrument)
        return "#{ins}@orderbook@#{depth}-futures" if VALID_FUTURES_ORDER_BOOK_DEPTHS.include?(depth)

        depths = VALID_FUTURES_ORDER_BOOK_DEPTHS.sort.join(", ")
        raise Errors::ValidationError,
              "futures order book channels are snapshot-based; documented depths are #{depths}"
      end

      def current_prices_futures
        CURRENT_PRICES_FUTURES_CHANNEL
      end

      def futures_price_stats(instrument:)
        "#{Contracts::Identifiers.validate_instrument!(instrument)}@prices-futures"
      end

      def futures_ltp(instrument:)
        futures_price_stats(instrument: instrument)
      end

      def futures_new_trade(instrument:)
        "#{Contracts::Identifiers.validate_instrument!(instrument)}@trades-futures"
      end
    end
  end
end
