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
        fallback_message: "request failed",
        category: :rate_limit,
        request_context: { endpoint: "/exchange/v1/orders/create", request_id: "request-123" },
        retryable: true
      )

      expect(normalized_error).to eq(
        success: false,
        data: {},
        error: {
          category: :rate_limit,
          code: "rate_limit",
          message: "too many requests",
          request_context: { endpoint: "/exchange/v1/orders/create", request_id: "request-123" },
          retryable: true
        },
        meta: { status: 429 }
      )
    end

    it "falls back to a readable message for string bodies" do
      normalized_error = described_class.failure(
        status: 500,
        body: "upstream failure",
        fallback_message: "request failed",
        category: :upstream,
        request_context: { endpoint: "/exchange/v1/orders/create" },
        retryable: false
      )

      expect(normalized_error).to eq(
        success: false,
        data: {},
        error: {
          category: :upstream,
          code: 500,
          message: "upstream failure",
          request_context: { endpoint: "/exchange/v1/orders/create" },
          retryable: false
        },
        meta: { status: 500 }
      )
    end
  end
end
