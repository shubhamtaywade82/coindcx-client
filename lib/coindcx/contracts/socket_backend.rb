# frozen_string_literal: true

module CoinDCX
  module Contracts
    module SocketBackend
      REQUIRED_METHODS = %i[connect emit on disconnect].freeze
      module_function

      def validate!(backend)
        missing_methods = REQUIRED_METHODS.reject { |method_name| backend.respond_to?(method_name) }
        return backend if missing_methods.empty?

        raise Errors::ConfigurationError,
              "socket backend must respond to #{REQUIRED_METHODS.join(', ')}; missing #{missing_methods.join(', ')}"
      end
    end
  end
end
