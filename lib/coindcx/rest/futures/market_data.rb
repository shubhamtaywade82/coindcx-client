# frozen_string_literal: true

module CoinDCX
  module REST
    module Futures
      class MarketData < BaseResource
        VALID_ORDER_BOOK_DEPTHS = [10, 20, 50].freeze

        def list_active_instruments(margin_currency_short_names: ["USDT"])
          get(
            "/exchange/v1/derivatives/futures/data/active_instruments",
            params: { 'margin_currency_short_name[]': margin_currency_short_names }
          )
        end

        def fetch_instrument(pair:, margin_currency_short_name:)
          build_model(
            Models::Instrument,
            get(
              "/exchange/v1/derivatives/futures/data/instrument",
              params: { pair: pair, margin_currency_short_name: margin_currency_short_name },
              body: {},
              auth: true,
              bucket: :futures_instrument_detail
            )
          )
        end

        def list_trades(pair:)
          build_models(Models::Trade, get("/exchange/v1/derivatives/futures/data/trades", params: { pair: pair }))
        end

        def fetch_order_book(instrument:, depth: 50)
          validate_order_book_depth!(depth)
          get("/market_data/v3/orderbook/#{instrument}-futures/#{depth}", base: :public)
        end

        def list_candlesticks(pair:, from:, to:, resolution:)
          get(
            "/market_data/candlesticks",
            base: :public,
            params: { pair: pair, from: from, to: to, resolution: resolution, pcode: "f" }
          )
        end

        def current_prices
          get("/market_data/v3/current_prices/futures/rt", base: :public, bucket: :public_market_data)
        end

        def stats(pair:)
          get(
            "/api/v1/derivatives/futures/data/stats",
            params: { pair: pair }
          )
        end

        def conversions
          get("/api/v1/derivatives/futures/data/conversions")
        end

        private

        def validate_order_book_depth!(depth)
          return depth if VALID_ORDER_BOOK_DEPTHS.include?(depth)

          raise Errors::ValidationError, "futures order book depth must be one of #{VALID_ORDER_BOOK_DEPTHS.join(', ')}"
        end
      end
    end
  end
end
