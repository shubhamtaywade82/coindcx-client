# frozen_string_literal: true

module CoinDCX
  module REST
    module Public
      class MarketData < BaseResource
        def list_tickers
          build_models(Models::Market, get("/exchange/ticker"))
        end

        def list_markets
          get("/exchange/v1/markets")
        end

        def list_market_details
          build_models(Models::Market, get("/exchange/v1/markets_details"))
        end

        def list_trades(pair:, limit: nil)
          build_models(
            Models::Trade,
            get("/market_data/trade_history", base: :public, params: { pair: pair, limit: limit })
          )
        end

        def fetch_order_book(pair:)
          get("/market_data/orderbook", base: :public, params: { pair: pair })
        end

        def list_candles(pair:, interval:, start_time: nil, end_time: nil, limit: nil)
          get(
            "/market_data/candles",
            base: :public,
            params: {
              pair: pair,
              interval: interval,
              startTime: start_time,
              endTime: end_time,
              limit: limit
            }
          )
        end
      end
    end
  end
end
