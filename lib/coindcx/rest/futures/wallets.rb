# frozen_string_literal: true

module CoinDCX
  module REST
    module Futures
      class Wallets < BaseResource
        def transfer(transfer_type:, amount:, currency_short_name:, timestamp: nil)
          post(
            "/exchange/v1/derivatives/futures/wallets/transfer",
            auth: true,
            body: {
              transfer_type: transfer_type,
              amount: amount,
              currency_short_name: currency_short_name,
              timestamp: timestamp
            }
          )
        end

        def fetch_details(attributes = {})
          post("/exchange/v1/derivatives/futures/wallets", auth: true, body: attributes)
        end

        def list_transactions(page: 1, size: 1000, timestamp: nil)
          post(
            "/exchange/v1/derivatives/futures/wallets/transactions",
            auth: true,
            body: { page: page, size: size, timestamp: timestamp }
          )
        end
      end
    end
  end
end
