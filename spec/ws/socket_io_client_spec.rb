# frozen_string_literal: true

require "spec_helper"

RSpec.describe CoinDCX::WS::SocketIOClient do
  let(:configuration) do
    CoinDCX::Configuration.new.tap do |config|
      config.api_key = "api-key"
      config.api_secret = "api-secret"
      config.socket_reconnect_attempts = 2
      config.socket_reconnect_interval = 0.01
    end
  end

  let(:backend) { instance_double("SocketBackend") }
  let(:sleeper) { class_double(Kernel, sleep: nil) }

  before do
    allow(backend).to receive(:on)
    allow(backend).to receive(:emit)
    allow(backend).to receive(:disconnect)
  end

  describe "#subscribe_public" do
    it "rejoins subscriptions after a reconnect event" do
      connect_callback = nil
      allow(backend).to receive(:connect)
      allow(backend).to receive(:on) do |event_name, &block|
        connect_callback = block if event_name == :connect
      end

      client = described_class.new(configuration: configuration, backend: backend, sleeper: sleeper)
      client.connect
      client.subscribe_public(channel_name: "B-BTC_USDT@prices", event_name: "price-change")

      expect(backend).to have_received(:emit).with("join", { "channelName" => "B-BTC_USDT@prices" }).once

      connect_callback.call

      expect(backend).to have_received(:emit).with("join", { "channelName" => "B-BTC_USDT@prices" }).twice
    end
  end

  describe "#connect" do
    it "retries socket connection failures with backoff" do
      allow(backend).to receive(:connect) do
        @connect_attempts ||= 0
        @connect_attempts += 1
        raise CoinDCX::Errors::SocketConnectionError, "temporary failure" if @connect_attempts == 1

        true
      end

      client = described_class.new(configuration: configuration, backend: backend, sleeper: sleeper)
      client.connect

      expect(backend).to have_received(:connect).twice
      expect(sleeper).to have_received(:sleep).with(0.01)
    end
  end
end
