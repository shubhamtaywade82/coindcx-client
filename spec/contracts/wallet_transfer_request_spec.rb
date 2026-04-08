# frozen_string_literal: true

require "spec_helper"

RSpec.describe CoinDCX::Contracts::WalletTransferRequest do
  describe ".validate_transfer!" do
    it "accepts a valid wallet transfer request" do
      attributes = described_class.validate_transfer!(
        source_wallet_type: "spot",
        destination_wallet_type: "futures",
        currency_short_name: "USDT",
        amount: 1
      )

      expect(attributes).to include(
        source_wallet_type: "spot",
        destination_wallet_type: "futures",
        currency_short_name: "USDT",
        amount: 1
      )
    end

    it "rejects unsupported wallet types" do
      expect do
        described_class.validate_transfer!(
          source_wallet_type: "vault",
          destination_wallet_type: "futures",
          currency_short_name: "USDT",
          amount: 1
        )
      end.to raise_error(CoinDCX::Errors::ValidationError, /source_wallet_type/)
    end

    it "rejects non-positive amounts" do
      expect do
        described_class.validate_transfer!(
          source_wallet_type: "spot",
          destination_wallet_type: "futures",
          currency_short_name: "USDT",
          amount: 0
        )
      end.to raise_error(CoinDCX::Errors::ValidationError, /amount/)
    end
  end
end
