# frozen_string_literal: true

require "spec_helper"

RSpec.describe CoinDCX::WS::Parsers::OrderBookSnapshot do
  describe ".parse" do
    it "normalizes the snapshot payload without pretending it is a diff stream" do
      parsed_snapshot = described_class.parse(
        "ts" => 1_705_483_019_891,
        "vs" => 27_570_132,
        "bids" => { "1995" => "2.618" },
        "asks" => { "2001" => "2.145" }
      )

      expect(parsed_snapshot).to eq(
        source: :snapshot,
        maximum_recent_orders: 50,
        timestamp: 1_705_483_019_891,
        version: 27_570_132,
        bids: [{ price: "1995", quantity: "2.618" }],
        asks: [{ price: "2001", quantity: "2.145" }]
      )
    end
  end
end
