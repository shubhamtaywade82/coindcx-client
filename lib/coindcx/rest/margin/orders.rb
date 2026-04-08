# frozen_string_literal: true

module CoinDCX
  module REST
    module Margin
      class Orders < BaseResource
        def create(attributes)
          build_model(Models::Order, post("/exchange/v1/margin/create", auth: true, body: attributes))
        end

        def list(attributes = {})
          build_models(Models::Order, post("/exchange/v1/margin/fetch_orders", auth: true, body: attributes))
        end

        def fetch(attributes)
          build_model(Models::Order, post("/exchange/v1/margin/order", auth: true, body: attributes))
        end

        def cancel(attributes)
          post("/exchange/v1/margin/cancel", auth: true, body: attributes)
        end

        def exit_order(attributes)
          post("/exchange/v1/margin/exit", auth: true, body: attributes)
        end

        def edit_target(attributes)
          post("/exchange/v1/margin/edit_target", auth: true, body: attributes)
        end

        def edit_stop_loss(attributes)
          post("/exchange/v1/margin/edit_sl", auth: true, body: attributes)
        end

        def edit_trailing_stop_loss(attributes)
          post("/exchange/v1/margin/edit_trailing_sl", auth: true, body: attributes)
        end

        def edit_target_order_price(attributes)
          post("/exchange/v1/margin/edit_price_of_target_order", auth: true, body: attributes)
        end

        def add_margin(attributes)
          post("/exchange/v1/margin/add_margin", auth: true, body: attributes)
        end

        def remove_margin(attributes)
          post("/exchange/v1/margin/remove_margin", auth: true, body: attributes)
        end
      end
    end
  end
end
