# frozen_string_literal: true

module CoinDCX
  module REST
    module Futures
      class Facade
        def initialize(http_client:)
          @http_client = http_client
        end

        def market_data
          @market_data ||= MarketData.new(http_client: @http_client)
        end

        def orders
          @orders ||= Orders.new(http_client: @http_client)
        end

        def positions
          @positions ||= Positions.new(http_client: @http_client)
        end

        def wallets
          @wallets ||= Wallets.new(http_client: @http_client)
        end
      end
    end
  end
end
