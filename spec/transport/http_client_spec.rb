# frozen_string_literal: true

require "faraday"
require "spec_helper"

RSpec.describe CoinDCX::Transport::HttpClient do
  let(:configuration) do
    CoinDCX::Configuration.new.tap do |config|
      config.api_key = "api-key"
      config.api_secret = "api-secret"
    end
  end

  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  subject(:http_client) { described_class.new(configuration: configuration, stubs: stubs) }

  describe "#post" do
    context "when the response is successful" do
      it "sends signed JSON to the API host" do
        stubs.post("/exchange/v1/orders/create") do |env|
          expect(env.request_headers["X-AUTH-APIKEY"]).to eq("api-key")
          expect(env.request_headers["X-AUTH-SIGNATURE"]).not_to be_nil
          expect(env.body).to include('"market":"SNTBTC"')
          [200, { "Content-Type" => "application/json" }, '{"id":"123"}']
        end

        response_body = http_client.post("/exchange/v1/orders/create", auth: true, body: { market: "SNTBTC" })

        expect(response_body).to eq("id" => "123")
        stubs.verify_stubbed_calls
      end
    end

    context "when CoinDCX responds with a rate limit error" do
      it "raises a rate limit error" do
        stubs.post("/exchange/v1/orders/create") do
          [429, { "Content-Type" => "application/json" }, '{"message":"too many requests"}']
        end

        request_call = lambda do
          http_client.post("/exchange/v1/orders/create", auth: true, body: { market: "SNTBTC" })
        end

        expect(&request_call).to raise_error(CoinDCX::Errors::RateLimitError) do |error|
          expect(error.status).to eq(429)
          expect(error.body).to eq("message" => "too many requests")
        end
      end
    end
  end
end
