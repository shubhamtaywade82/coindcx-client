# frozen_string_literal: true

require "spec_helper"

RSpec.describe CoinDCX::Contracts::OrderRequest do
  describe ".validate_spot_create!" do
    it "accepts a valid spot order" do
      attributes = described_class.validate_spot_create!(
        side: "buy",
        order_type: "limit_order",
        market: "SNTBTC",
        total_quantity: 2,
        price_per_unit: "0.03244"
      )

      expect(attributes).to include(
        side: "buy",
        order_type: "limit_order",
        market: "SNTBTC",
        total_quantity: 2
      )
    end

    it "rejects unsupported sides" do
      expect do
        described_class.validate_spot_create!(
          side: "hold",
          order_type: "limit_order",
          market: "SNTBTC",
          total_quantity: 2
        )
      end.to raise_error(CoinDCX::Errors::ValidationError, /side/)
    end

    it "rejects non-positive quantities" do
      expect do
        described_class.validate_spot_create!(
          side: "buy",
          order_type: "limit_order",
          market: "SNTBTC",
          total_quantity: 0
        )
      end.to raise_error(CoinDCX::Errors::ValidationError, /total_quantity/)
    end

    it "rejects invalid market symbols" do
      expect do
        described_class.validate_spot_create!(
          side: "buy",
          order_type: "limit_order",
          market: "btc-usdt",
          total_quantity: 1
        )
      end.to raise_error(CoinDCX::Errors::ValidationError, /market/)
    end
  end

  describe ".validate_futures_create!" do
    it "accepts a valid futures order" do
      order = described_class.validate_futures_create!(
        side: "sell",
        order_type: "limit_order",
        pair: "B-BTC_USDT",
        quantity: 1
      )

      expect(order).to include(side: "sell", pair: "B-BTC_USDT", quantity: 1)
    end

    it "accepts total_quantity (CoinDCX futures create payload style)" do
      order = described_class.validate_futures_create!(
        side: "buy",
        pair: "B-SOL_USDT",
        total_quantity: "0.01",
        order_type: "market_order",
        margin_currency_short_name: "USDT",
        leverage: 3
      )

      expect(order).to include(side: "buy", pair: "B-SOL_USDT", total_quantity: "0.01")
    end

    it "rejects malformed pair identifiers" do
      expect do
        described_class.validate_futures_create!(
          side: "sell",
          pair: "BTCUSDT",
          quantity: 1
        )
      end.to raise_error(CoinDCX::Errors::ValidationError, /pair/)
    end
  end

  describe ".validate_margin_create!" do
    it "accepts a valid margin order" do
      attributes = described_class.validate_margin_create!(
        side: "buy",
        order_type: "market_order",
        market: "SNTBTC",
        quantity: 1
      )

      expect(attributes).to include(side: "buy", market: "SNTBTC", quantity: 1)
    end

    it "rejects missing quantities" do
      expect do
        described_class.validate_margin_create!(
          side: "buy",
          order_type: "market_order",
          market: "SNTBTC"
        )
      end.to raise_error(CoinDCX::Errors::ValidationError, /quantity/)
    end
  end
end
