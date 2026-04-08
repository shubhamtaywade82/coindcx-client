# frozen_string_literal: true

require "spec_helper"

RSpec.describe CoinDCX::WS::PublicChannels do
  describe ".order_book" do
    it "builds a documented snapshot channel" do
      expect(described_class.order_book(pair: "B-BTC_USDT", depth: 20)).to eq("B-BTC_USDT@orderbook@20")
    end

    it "rejects unsupported spot depths" do
      expect do
        described_class.order_book(pair: "B-BTC_USDT", depth: 10)
      end.to raise_error(CoinDCX::Errors::ValidationError, /snapshot-based/)
    end
  end
end
