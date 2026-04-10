# frozen_string_literal: true

module CoinDCX
  module REST
    module Funding
      # Funding endpoints for lend, settle, and order-history flows.
      class Orders < BaseResource
        # Fetches funding orders for the authenticated account.
        # @param attributes [Hash] request filters accepted by CoinDCX
        # @return [Hash] raw CoinDCX payload
        def list(attributes = {})
          post(
            "/exchange/v1/funding/fetch_orders",
            auth: true,
            bucket: :funding_fetch_orders,
            body: attributes
          )
        end

        # Places a funding lend order.
        # @param attributes [Hash] lend payload accepted by CoinDCX
        # @return [Hash] raw CoinDCX payload
        def lend(attributes)
          post(
            "/exchange/v1/funding/lend",
            auth: true,
            bucket: :funding_lend,
            body: attributes
          )
        end

        # Settles a funding order.
        # @param attributes [Hash] settle payload accepted by CoinDCX
        # @return [Hash] raw CoinDCX payload
        def settle(attributes)
          post(
            "/exchange/v1/funding/settle",
            auth: true,
            bucket: :funding_settle,
            body: attributes
          )
        end
      end
    end
  end
end
