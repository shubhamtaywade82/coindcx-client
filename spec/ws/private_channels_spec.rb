# frozen_string_literal: true

require "json"
require "openssl"
require "spec_helper"

RSpec.describe CoinDCX::WS::PrivateChannels do
  subject(:private_channels) do
    described_class.new(
      configuration: CoinDCX::Configuration.new.tap do |config|
        config.api_key = "api-key"
        config.api_secret = "api-secret"
      end
    )
  end

  describe "#join_payload" do
    it "signs the fixed private channel payload" do
      expected_signature = OpenSSL::HMAC.hexdigest("SHA256", "api-secret", JSON.generate("channel" => "coindcx"))

      expect(private_channels.join_payload).to eq(
        "channelName" => "coindcx",
        "authSignature" => expected_signature,
        "apiKey" => "api-key"
      )
    end
  end
end
