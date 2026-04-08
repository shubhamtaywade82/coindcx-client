# frozen_string_literal: true

require "json"
require "openssl"
require "spec_helper"

RSpec.describe CoinDCX::Auth::Signer do
  subject(:signer) { described_class.new(api_key: "key-123", api_secret: "secret-456") }

  describe "#authenticated_request" do
    it "adds the documented authentication headers" do
      request_body, headers = signer.authenticated_request(market: "SNTBTC", timestamp: 1234)
      expected_signature = OpenSSL::HMAC.hexdigest("SHA256", "secret-456", JSON.generate("market" => "SNTBTC", "timestamp" => 1234))

      expect(request_body).to eq(market: "SNTBTC", timestamp: 1234)
      expect(headers).to eq(
        "X-AUTH-APIKEY" => "key-123",
        "X-AUTH-SIGNATURE" => expected_signature
      )
    end
  end
end
