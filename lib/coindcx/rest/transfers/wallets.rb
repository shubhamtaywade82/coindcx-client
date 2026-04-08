# frozen_string_literal: true

module CoinDCX
  module REST
    module Transfers
      class Wallets < BaseResource
        def transfer(source_wallet_type:, destination_wallet_type:, currency_short_name:, amount:, timestamp: nil)
          validated_attributes = Contracts::WalletTransferRequest.validate_transfer!(
            source_wallet_type: source_wallet_type,
            destination_wallet_type: destination_wallet_type,
            currency_short_name: currency_short_name,
            amount: amount,
            timestamp: timestamp
          )
          post(
            "/exchange/v1/wallets/transfer",
            auth: true,
            bucket: :wallets_transfer,
            body: validated_attributes
          )
        end

        def sub_account_transfer(from_account_id:, to_account_id:, currency_short_name:, amount:, timestamp: nil)
          post(
            "/exchange/v1/wallets/sub_account_transfer",
            auth: true,
            bucket: :wallets_sub_account_transfer,
            body: {
              from_account_id: from_account_id,
              to_account_id: to_account_id,
              currency_short_name: currency_short_name,
              amount: amount,
              timestamp: timestamp
            }
          )
        end
      end
    end
  end
end
