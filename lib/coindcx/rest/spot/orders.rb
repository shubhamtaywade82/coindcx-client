# frozen_string_literal: true

module CoinDCX
  module REST
    module Spot
      class Orders < BaseResource
        def create(attributes)
          build_model(Models::Order, post("/exchange/v1/orders/create", auth: true, bucket: :spot_create_order, body: attributes))
        end

        def create_many(orders:)
          build_models(
            Models::Order,
            post("/exchange/v1/orders/create_multiple", auth: true, bucket: :spot_create_order_multiple, body: { orders: orders })
          )
        end

        def fetch_status(attributes)
          build_model(Models::Order, post("/exchange/v1/orders/status", auth: true, bucket: :spot_order_status, body: attributes))
        end

        def fetch_statuses(attributes)
          build_models(
            Models::Order,
            post("/exchange/v1/orders/status_multiple", auth: true, bucket: :spot_order_status_multiple, body: attributes)
          )
        end

        def list_active(attributes = {})
          build_models(
            Models::Order,
            post("/exchange/v1/orders/active_orders", auth: true, bucket: :spot_active_order, body: attributes)
          )
        end

        def count_active(attributes = {})
          post("/exchange/v1/orders/active_orders_count", auth: true, body: attributes)
        end

        def list_trade_history(attributes = {})
          build_models(Models::Trade, post("/exchange/v1/orders/trade_history", auth: true, body: attributes))
        end

        def cancel(attributes)
          build_model(Models::Order, post("/exchange/v1/orders/cancel", auth: true, bucket: :spot_cancel_order, body: attributes))
        end

        def cancel_many(attributes)
          build_models(
            Models::Order,
            post("/exchange/v1/orders/cancel_by_ids", auth: true, bucket: :spot_cancel_multiple_by_id, body: attributes)
          )
        end

        def cancel_all(attributes = {})
          post("/exchange/v1/orders/cancel_all", auth: true, bucket: :spot_cancel_all, body: attributes)
        end

        def edit_price(attributes)
          build_model(Models::Order, post("/exchange/v1/orders/edit", auth: true, bucket: :spot_edit_price, body: attributes))
        end
      end
    end
  end
end
