# frozen_string_literal: true

require "spec_helper"

RSpec.describe CoinDCX::WS::PublicChannels do
  describe ".order_book" do
    it "builds documented snapshot channels for depths 10, 20, and 50" do
      [10, 20, 50].each do |depth|
        expect(described_class.order_book(pair: "B-BTC_USDT", depth: depth)).to eq("B-BTC_USDT@orderbook@#{depth}")
      end
    end

    it "rejects unsupported spot depths" do
      expect do
        described_class.order_book(pair: "B-BTC_USDT", depth: 5)
      end.to raise_error(CoinDCX::Errors::ValidationError, /snapshot-based/)
    end
  end

  describe ".current_prices_spot" do
    it "builds currentPrices@spot channels for 1s and 10s" do
      expect(described_class.current_prices_spot(interval: "1s")).to eq("currentPrices@spot@1s")
      expect(described_class.current_prices_spot(interval: "10s")).to eq("currentPrices@spot@10s")
    end

    it "rejects unsupported intervals" do
      expect do
        described_class.current_prices_spot(interval: "30s")
      end.to raise_error(CoinDCX::Errors::ValidationError, /currentPrices@spot/)
    end
  end

  describe ".price_stats_spot" do
    it "builds the 60s priceStats@spot channel" do
      expect(described_class.price_stats_spot).to eq("priceStats@spot@60s")
    end
  end
end
