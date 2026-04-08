# frozen_string_literal: true

module CoinDCX
  module Contracts
    module WalletTransferRequest
      VALID_WALLET_TYPES = %w[spot futures margin].freeze

      module_function

      def validate_transfer!(attributes)
        validate_wallet_type!(attributes, :source_wallet_type)
        validate_wallet_type!(attributes, :destination_wallet_type)
        validate_positive_number!(attributes, :amount)
        validate_currency!(attributes, :currency_short_name)
        attributes
      end

      def validate_wallet_type!(attributes, key)
        wallet_type = fetch_required(attributes, key)
        return wallet_type if VALID_WALLET_TYPES.include?(wallet_type.to_s)

        raise Errors::ValidationError, "#{key} must be one of: #{VALID_WALLET_TYPES.join(', ')}"
      end

      def validate_positive_number!(attributes, key)
        number = fetch_required(attributes, key)
        return number if number.to_f.positive?

        raise Errors::ValidationError, "#{key} must be greater than 0"
      end

      def validate_currency!(attributes, key)
        Identifiers.validate_currency!(fetch_required(attributes, key))
      end

      def fetch_required(attributes, key)
        return attributes[key] if attributes.key?(key)
        return attributes[key.to_s] if attributes.key?(key.to_s)

        raise Errors::ValidationError, "#{key} is required"
      end

      private_class_method :validate_wallet_type!, :validate_positive_number!, :validate_currency!, :fetch_required
    end
  end
end
