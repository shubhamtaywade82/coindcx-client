# frozen_string_literal: true

module CoinDCX
  module REST
    module Public
      class Facade
        def initialize(http_client:)
          @http_client = http_client
        end

        def market_data
          @market_data ||= MarketData.new(http_client: @http_client)
        end
      end
    end
  end
end
