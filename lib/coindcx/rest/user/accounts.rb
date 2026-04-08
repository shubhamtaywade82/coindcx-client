# frozen_string_literal: true

module CoinDCX
  module REST
    module User
      class Accounts < BaseResource
        def list_balances(attributes = {})
          build_models(Models::Balance, post("/exchange/v1/users/balances", auth: true, bucket: :user_balances, body: attributes))
        end

        def fetch_info(attributes = {})
          post("/exchange/v1/users/info", auth: true, bucket: :user_info, body: attributes)
        end
      end
    end
  end
end
