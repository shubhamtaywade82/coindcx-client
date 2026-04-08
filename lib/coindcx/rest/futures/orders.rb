# frozen_string_literal: true

module CoinDCX
  module REST
    module Futures
      class Orders < BaseResource
        def list(attributes = {})
          build_models(Models::Order, post("/exchange/v1/derivatives/futures/orders", auth: true, body: attributes))
        end

        def create(order:)
          build_model(Models::Order, post("/exchange/v1/derivatives/futures/orders/create", auth: true, body: { order: order }))
        end

        def cancel(attributes)
          post("/exchange/v1/derivatives/futures/orders/cancel", auth: true, body: attributes)
        end

        def edit(attributes)
          build_model(Models::Order, post("/exchange/v1/derivatives/futures/orders/edit", auth: true, body: attributes))
        end
      end
    end
  end
end
