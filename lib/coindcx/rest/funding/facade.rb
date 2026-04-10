# frozen_string_literal: true

module CoinDCX
  module REST
    module Funding
      # Funding facade exposing CoinDCX funding-order APIs.
      class Facade
        def initialize(http_client:)
          @http_client = http_client
        end

        def orders
          @orders ||= Orders.new(http_client: @http_client)
        end
      end
    end
  end
end
