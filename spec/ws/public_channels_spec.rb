# frozen_string_literal: true

require "spec_helper"

RSpec.describe CoinDCX::WS::PublicChannels do
  describe "event constants" do
    it "exposes documented public event names" do
      expect(described_class::CANDLESTICK_EVENT).to eq("candlestick")
      expect(described_class::DEPTH_SNAPSHOT_EVENT).to eq("depth-snapshot")
      expect(described_class::DEPTH_UPDATE_EVENT).to eq("depth-update")
      expect(described_class::NEW_TRADE_EVENT).to eq("new-trade")
      expect(described_class::PRICE_CHANGE_EVENT).to eq("price-change")
    end
  end

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

  describe ".futures_candlestick" do
    it "suffixes the instrument channel with interval and -futures per CoinDCX docs" do
      expect(described_class.futures_candlestick(instrument: "B-BTC_USDT", interval: "1m")).to eq("B-BTC_USDT_1m-futures")
    end

    it "rejects a blank interval" do
      expect do
        described_class.futures_candlestick(instrument: "B-BTC_USDT", interval: "  ")
      end.to raise_error(CoinDCX::Errors::ValidationError, /interval/)
    end
  end

  describe ".futures_order_book" do
    it "builds documented futures snapshot channels for depths 10, 20, and 50" do
      [10, 20, 50].each do |depth|
        expect(described_class.futures_order_book(instrument: "B-BTC_USDT", depth: depth)).to eq(
          "B-BTC_USDT@orderbook@#{depth}-futures"
        )
      end
    end

    it "rejects unsupported futures depths" do
      expect do
        described_class.futures_order_book(instrument: "B-BTC_USDT", depth: 5)
      end.to raise_error(CoinDCX::Errors::ValidationError, /documented depths/)
    end
  end

  describe ".current_prices_futures" do
    it "returns the currentPrices@futures@rt channel" do
      expect(described_class.current_prices_futures).to eq("currentPrices@futures@rt")
    end
  end

  describe "futures LTP and trade channels" do
    it "builds @prices-futures and @trades-futures" do
      expect(described_class.futures_ltp(instrument: "B-ETH_USDT")).to eq("B-ETH_USDT@prices-futures")
      expect(described_class.futures_new_trade(instrument: "B-ETH_USDT")).to eq("B-ETH_USDT@trades-futures")
    end
  end
end
