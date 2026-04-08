# frozen_string_literal: true

module CoinDCX
  module REST
    module Transfers
      class Facade
        def initialize(http_client:)
          @http_client = http_client
        end

        def wallets
          @wallets ||= Wallets.new(http_client: @http_client)
        end
      end
    end
  end
end
