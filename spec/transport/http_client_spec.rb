# frozen_string_literal: true

require "faraday"
require "spec_helper"

RSpec.describe CoinDCX::Transport::HttpClient do
  let(:configuration) do
    CoinDCX::Configuration.new.tap do |config|
      config.api_key = "api-key"
      config.api_secret = "api-secret"
      config.logger = logger
      config.retry_base_interval = 0.01
    end
  end

  let(:logger) { instance_double("Logger", info: nil, warn: nil, error: nil) }
  let(:sleeper) { class_double(Kernel, sleep: nil) }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  subject(:http_client) { described_class.new(configuration: configuration, stubs: stubs, sleeper: sleeper) }

  describe "#get" do
    context "when authenticated with a JSON body (CoinDCX futures wallet-style GET)" do
      it "sends signed JSON in the request body and query params on the URL" do
        stubs.get("/exchange/v1/derivatives/futures/wallets/transactions") do |env|
          expect(env.request_headers["X-AUTH-APIKEY"]).to eq("api-key")
          expect(env.request_headers["X-AUTH-SIGNATURE"]).not_to be_nil
          expect(env.body).to match(/"timestamp":\d+/)
          expect(env.url.query).to eq("page=1&size=10")
          [200, { "Content-Type" => "application/json" }, "[]"]
        end

        response_body = http_client.get(
          "/exchange/v1/derivatives/futures/wallets/transactions",
          params: { page: 1, size: 10 },
          body: {},
          auth: true,
          bucket: :futures_wallet_transactions
        )

        expect(response_body).to eq([])
        stubs.verify_stubbed_calls
      end
    end
  end

  describe "#post" do
    context "when the response is successful" do
      it "returns the parsed response data and logs the request metadata" do
        stubs.post("/exchange/v1/orders/create") do |env|
          expect(env.request_headers["X-AUTH-APIKEY"]).to eq("api-key")
          expect(env.request_headers["X-AUTH-SIGNATURE"]).not_to be_nil
          expect(env.body).to include('"market":"SNTBTC"')
          [200, { "Content-Type" => "application/json" }, '{"id":"123"}']
        end

        response_body = http_client.post(
          "/exchange/v1/orders/create",
          auth: true,
          bucket: :spot_create_order,
          body: { market: "SNTBTC" }
        )

        expect(response_body).to eq("id" => "123")
        expect(logger).to have_received(:info).with(
          hash_including(
            event: "api_call",
            endpoint: "/exchange/v1/orders/create",
            request_id: a_string_matching(/\A[0-9a-f\-]{36}\z/),
            retries: 0
          )
        )
        stubs.verify_stubbed_calls
      end
    end

    context "when CoinDCX responds with a rate limit error" do
      it "raises a rate limit error" do
        stubs.post("/exchange/v1/orders/create") do
          [429, { "Content-Type" => "application/json" }, '{"message":"too many requests"}']
        end

        request_call = lambda do
          http_client.post(
            "/exchange/v1/orders/create",
            auth: true,
            bucket: :spot_create_order,
            body: { market: "SNTBTC" }
          )
        end

        expect(&request_call).to raise_error(CoinDCX::Errors::RateLimitError) do |error|
          expect(error.status).to eq(429)
          expect(error.body).to include(success: false, data: {})
          expect(error.body[:error]).to include(
            category: :rate_limit,
            code: 429,
            message: "too many requests",
            retryable: false
          )
          expect(error.body.dig(:error, :request_context)).to include(
            base: :api,
            endpoint: "/exchange/v1/orders/create",
            method: "POST",
            operation: "post_exchange_v1_orders_create"
          )
          expect(error.body.dig(:error, :request_context, :request_id)).to match(/\A[0-9a-f-]{36}\z/)
        end
      end
    end

    context "when CoinDCX responds with a retryable rate limit error" do
      it "retries when Retry-After is present and the endpoint budget allows it" do
        attempts = 0
        stubs.post("/exchange/v1/orders/status") do
          attempts += 1
          if attempts == 1
            [429, { "Content-Type" => "application/json", "Retry-After" => "0.5" }, '{"message":"slow down"}']
          else
            [200, { "Content-Type" => "application/json" }, '{"id":"123"}']
          end
        end

        response_body = http_client.post("/exchange/v1/orders/status", auth: true, body: { id: "123" }, bucket: :spot_order_status)

        expect(response_body).to eq("id" => "123")
        expect(attempts).to eq(2)
        expect(sleeper).to have_received(:sleep).with(0.5).once
      end
    end

    context "when CoinDCX responds with a retryable upstream error" do
      it "retries a private read endpoint within its retry budget" do
        attempts = 0
        stubs.post("/exchange/v1/orders/status") do
          attempts += 1
          if attempts == 1
            [503, { "Content-Type" => "application/json" }, '{"message":"temporary outage"}']
          else
            [200, { "Content-Type" => "application/json" }, '{"id":"123"}']
          end
        end

        response_body = http_client.post("/exchange/v1/orders/status", auth: true, body: { id: "123" }, bucket: :spot_order_status)

        expect(response_body).to eq("id" => "123")
        expect(attempts).to eq(2)
        expect(logger).to have_received(:warn).with(
          hash_including(
            event: "api_retry",
            endpoint: "/exchange/v1/orders/status",
            retries: 1
          )
        )
      end
    end

    context "when an order create request times out without an idempotency key" do
      it "does not retry the request" do
        attempts = 0
        stubs.post("/exchange/v1/orders/create") do
          attempts += 1
          raise Faraday::TimeoutError, "timed out"
        end

        expect do
          http_client.post(
            "/exchange/v1/orders/create",
            auth: true,
            bucket: :spot_create_order,
            body: { market: "SNTBTC" }
          )
        end.to raise_error(CoinDCX::Errors::TransportError, /CoinDCX transport failed for \/exchange\/v1\/orders\/create/)

        expect(attempts).to eq(1)
        expect(sleeper).not_to have_received(:sleep)
      end
    end

    context "when an order create request times out with an idempotency key" do
      it "retries the request" do
        attempts = 0
        stubs.post("/exchange/v1/orders/create") do
          attempts += 1
          raise Faraday::TimeoutError, "timed out" if attempts == 1

          [200, { "Content-Type" => "application/json" }, '{"id":"123"}']
        end

        response_body = http_client.post(
          "/exchange/v1/orders/create",
          auth: true,
          bucket: :spot_create_order,
          body: { market: "SNTBTC", client_order_id: "client-123" }
        )

        expect(response_body).to eq("id" => "123")
        expect(attempts).to eq(2)
        expect(sleeper).to have_received(:sleep).with(0.01).once
        expect(logger).to have_received(:warn).with(
          hash_including(
            event: "api_retry",
            endpoint: "/exchange/v1/orders/create",
            retries: 1
          )
        )
      end
    end

    context "when an upstream error repeatedly hits a critical order endpoint" do
      it "opens the circuit breaker for subsequent calls" do
        configuration.circuit_breaker_threshold = 2
        configuration.idempotent_order_retry_budget = 0

        failing_client = described_class.new(configuration: configuration, stubs: stubs, sleeper: sleeper)
        stubs.post("/exchange/v1/orders/create") do
          [503, { "Content-Type" => "application/json" }, '{"message":"temporary outage"}']
        end

        2.times do
          expect do
            failing_client.post(
              "/exchange/v1/orders/create",
              auth: true,
              bucket: :spot_create_order,
              body: { market: "SNTBTC", client_order_id: "client-123" }
            )
          end.to raise_error(CoinDCX::Errors::UpstreamServerError)
        end

        expect do
          failing_client.post(
            "/exchange/v1/orders/create",
            auth: true,
            bucket: :spot_create_order,
            body: { market: "SNTBTC", client_order_id: "client-123" }
          )
        end.to raise_error(CoinDCX::Errors::CircuitOpenError)
      end
    end
  end
end
