# frozen_string_literal: true

module CoinDCX
  module REST
    module Futures
      class Positions < BaseResource
        def list(attributes = {})
          post("/exchange/v1/derivatives/futures/positions", auth: true, body: attributes)
        end

        def update_leverage(attributes)
          post("/exchange/v1/derivatives/futures/positions/update_leverage", auth: true, body: attributes)
        end

        def add_margin(attributes)
          post("/exchange/v1/derivatives/futures/positions/add_margin", auth: true, body: attributes)
        end

        def remove_margin(attributes)
          post("/exchange/v1/derivatives/futures/positions/remove_margin", auth: true, body: attributes)
        end

        def cancel_all_open_orders(attributes)
          post("/exchange/v1/derivatives/futures/positions/cancel_all_open_orders", auth: true, body: attributes)
        end

        def cancel_all_open_orders_for_position(attributes)
          post("/exchange/v1/derivatives/futures/positions/cancel_all_open_orders_for_position", auth: true, body: attributes)
        end

        def exit_position(attributes)
          post("/exchange/v1/derivatives/futures/positions/exit", auth: true, body: attributes)
        end

        def create_take_profit_stop_loss(attributes)
          post("/exchange/v1/derivatives/futures/positions/create_tpsl", auth: true, body: attributes)
        end

        def list_transactions(attributes = {})
          post("/exchange/v1/derivatives/futures/positions/transactions", auth: true, body: attributes)
        end

        def fetch_cross_margin_details(attributes = {})
          get("/exchange/v1/derivatives/futures/positions/cross_margin_details", body: attributes, auth: true)
        end

        def update_margin_type(attributes)
          post("/exchange/v1/derivatives/futures/positions/margin_type", auth: true, body: attributes)
        end
      end
    end
  end
end
