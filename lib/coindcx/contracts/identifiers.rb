# frozen_string_literal: true

module CoinDCX
  module Contracts
    module Identifiers
      MARKET_PATTERN = /\A[A-Z0-9]+\z/.freeze
      PAIR_PATTERN = /\A[A-Z]+-[A-Z0-9]+_[A-Z0-9]+\z/.freeze
      CURRENCY_PATTERN = /\A[A-Z0-9]+\z/.freeze

      module_function

      def validate_market!(market)
        validate!(market, MARKET_PATTERN, "market must be a CoinDCX symbol like SNTBTC")
      end

      def validate_pair!(pair)
        validate!(pair, PAIR_PATTERN, "pair must be a CoinDCX pair like B-BTC_USDT")
      end

      def validate_instrument!(instrument)
        validate_pair!(instrument)
      end

      def validate_currency!(currency)
        validate!(currency, CURRENCY_PATTERN, "currency_short_name must be a CoinDCX currency code")
      end

      def validate!(value, pattern, message)
        string_value = value.to_s.strip
        raise Errors::ValidationError, message if string_value.empty? || string_value.match?(pattern) == false

        string_value
      end
    end
  end
end
