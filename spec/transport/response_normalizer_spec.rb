# frozen_string_literal: true

require "spec_helper"

RSpec.describe CoinDCX::Transport::ResponseNormalizer do
  describe ".success" do
    it "wraps response data in a consistent success shape" do
      expect(described_class.success("id" => "123")).to eq(
        success: true,
        data: { "id" => "123" },
        error: nil
      )
    end
  end

  describe ".failure" do
    it "extracts normalized error details from a hash body" do
      normalized_error = described_class.failure(
        status: 429,
        body: { "message" => "too many requests", "code" => "rate_limit" },
        fallback_message: "request failed"
      )

      expect(normalized_error).to eq(
        success: false,
        data: {},
        error: {
          code: "rate_limit",
          message: "too many requests"
        }
      )
    end

    it "falls back to a readable message for string bodies" do
      normalized_error = described_class.failure(
        status: 500,
        body: "upstream failure",
        fallback_message: "request failed"
      )

      expect(normalized_error).to eq(
        success: false,
        data: {},
        error: {
          code: 500,
          message: "upstream failure"
        }
      )
    end
  end
end
