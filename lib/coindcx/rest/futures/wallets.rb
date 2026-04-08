# frozen_string_literal: true

module CoinDCX
  module REST
    module Futures
      class Wallets < BaseResource
        def transfer(transfer_type:, amount:, currency_short_name:, timestamp: nil)
          post(
            "/exchange/v1/derivatives/futures/wallets/transfer",
            auth: true,
            bucket: :futures_wallet_transfer,
            body: {
              transfer_type: transfer_type,
              amount: amount,
              currency_short_name: currency_short_name,
              timestamp: timestamp
            }
          )
        end

        def fetch_details(attributes = {})
          get(
            "/exchange/v1/derivatives/futures/wallets",
            body: attributes,
            auth: true,
            bucket: :futures_wallet_details
          )
        end

        def list_transactions(page: 1, size: 1000, timestamp: nil)
          body = {}
          body[:timestamp] = timestamp unless timestamp.nil?
          get(
            "/exchange/v1/derivatives/futures/wallets/transactions",
            params: { page: page, size: size },
            body: body,
            auth: true,
            bucket: :futures_wallet_transactions
          )
        end
      end
    end
  end
end
