# frozen_string_literal: true

module CoinDCX
  module REST
    module User
      class Accounts < BaseResource
        def list_balances(attributes = {})
          build_models(Models::Balance, post("/exchange/v1/users/balances", auth: true, body: attributes))
        end

        def fetch_info(attributes = {})
          post("/exchange/v1/users/info", auth: true, body: attributes)
        end
      end
    end
  end
end
