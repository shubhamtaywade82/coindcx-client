# frozen_string_literal: true

require "spec_helper"

RSpec.describe CoinDCX::Transport::RequestPolicy do
  let(:configuration) { CoinDCX::Configuration.new }

  describe ".build" do
    it "marks order create endpoints as idempotency-required" do
      policy = described_class.build(
        configuration: configuration,
        method: :post,
        path: "/exchange/v1/orders/create",
        body: { market: "SNTBTC", client_order_id: "spot-1" },
        auth: true,
        bucket: :spot_create_order
      )

      expect(policy.requires_idempotency?).to be(true)
      expect(policy.idempotency_satisfied?).to be(true)
      expect(policy.retry_budget).to eq(configuration.idempotent_order_retry_budget)
    end

    it "disables retries when idempotency is missing on unsafe endpoints" do
      policy = described_class.build(
        configuration: configuration,
        method: :post,
        path: "/exchange/v1/orders/create",
        body: { market: "SNTBTC" },
        auth: true,
        bucket: :spot_create_order
      )

      expect(policy.requires_idempotency?).to be(true)
      expect(policy.idempotency_satisfied?).to be(false)
      expect(policy.retry_budget).to eq(0)
    end

    it "requires every batch order to carry an idempotency key" do
      policy = described_class.build(
        configuration: configuration,
        method: :post,
        path: "/exchange/v1/orders/create_multiple",
        body: { orders: [{ market: "SNTBTC", client_order_id: "spot-1" }, { market: "ETHBTC" }] },
        auth: true,
        bucket: :spot_create_order_multiple
      )

      expect(policy.requires_idempotency?).to be(true)
      expect(policy.idempotency_satisfied?).to be(false)
      expect(policy.retry_budget).to eq(0)
    end
  end
end
