# frozen_string_literal: true

module CoinDCX
  module REST
    module User
      class Facade
        def initialize(http_client:)
          @http_client = http_client
        end

        def accounts
          @accounts ||= Accounts.new(http_client: @http_client)
        end
      end
    end
  end
end
