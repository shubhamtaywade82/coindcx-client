# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CoinDCX::REST::Futures::Orders do
  subject(:resource) { described_class.new(http_client: http_client) }

  let(:http_client) { instance_double(CoinDCX::Transport::HttpClient) }

  before do
    allow(http_client).to receive(:post).and_return({})
  end

  describe "#create" do
    it "validates futures order payloads and applies a create-order bucket" do
      resource.create(order: { side: "sell", quantity: 2, client_order_id: "futures-123" })

      expect(http_client).to have_received(:post).with(
        "/exchange/v1/derivatives/futures/orders/create",
        body: { order: { side: "sell", quantity: 2, client_order_id: "futures-123" } },
        auth: true,
        base: :api,
        bucket: :futures_create_order
      )
    end

    it "accepts total_quantity for bot-style market orders" do
      resource.create(
        order: {
          side: "buy",
          pair: "B-SOL_USDT",
          total_quantity: "0.05",
          order_type: "market_order",
          client_order_id: "futures-124",
          leverage: 2
        }
      )

      expect(http_client).to have_received(:post).with(
        "/exchange/v1/derivatives/futures/orders/create",
        body: {
          order: {
            side: "buy",
            pair: "B-SOL_USDT",
            total_quantity: "0.05",
            order_type: "market_order",
            client_order_id: "futures-124",
            leverage: 2
          }
        },
        auth: true,
        base: :api,
        bucket: :futures_create_order
      )
    end

    it "rejects an invalid side" do
      expect do
        resource.create(order: { side: "wait", quantity: 2 })
      end.to raise_error(CoinDCX::Errors::ValidationError, /side/)
    end

    it "rejects a non-positive quantity" do
      expect do
        resource.create(order: { side: "buy", quantity: 0 })
      end.to raise_error(CoinDCX::Errors::ValidationError, /quantity/)
    end
  end

  describe "authenticated routing" do
    it "routes futures order operations through authenticated transport calls" do
      resource.list
      resource.list_trades
      resource.cancel(id: "1")
      resource.edit(id: "1")

      expect(http_client).to have_received(:post).with(
        "/exchange/v1/derivatives/futures/orders",
        body: {},
        auth: true,
        base: :api,
        bucket: :futures_list_orders
      )
      expect(http_client).to have_received(:post).with(
        "/exchange/v1/derivatives/futures/orders/cancel",
        body: { id: "1" },
        auth: true,
        base: :api,
        bucket: :futures_cancel_order
      )
      expect(http_client).to have_received(:post).with(
        "/exchange/v1/derivatives/futures/trades",
        body: {},
        auth: true,
        base: :api,
        bucket: :futures_trades
      )
      expect(http_client).to have_received(:post).with(
        "/exchange/v1/derivatives/futures/orders/edit",
        body: { id: "1" },
        auth: true,
        base: :api,
        bucket: :futures_edit_order
      )
    end
  end
end
