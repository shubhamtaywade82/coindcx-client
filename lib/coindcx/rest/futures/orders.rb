# frozen_string_literal: true

module CoinDCX
  module REST
    module Futures
      class Orders < BaseResource
        def list(attributes = {})
          build_models(
            Models::Order,
            post("/exchange/v1/derivatives/futures/orders", auth: true, bucket: :futures_list_orders, body: attributes)
          )
        end

        def create(order:)
          validated_order = Contracts::OrderRequest.validate_futures_create!(order)
          build_model(
            Models::Order,
            post(
              "/exchange/v1/derivatives/futures/orders/create",
              auth: true,
              bucket: :futures_create_order,
              body: { order: validated_order }
            )
          )
        end

        def cancel(attributes)
          post("/exchange/v1/derivatives/futures/orders/cancel", auth: true, bucket: :futures_cancel_order, body: attributes)
        end

        def edit(attributes)
          build_model(
            Models::Order,
            post("/exchange/v1/derivatives/futures/orders/edit", auth: true, bucket: :futures_edit_order, body: attributes)
          )
        end
      end
    end
  end
end
