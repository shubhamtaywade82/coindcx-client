# frozen_string_literal: true

require "spec_helper"

RSpec.describe CoinDCX::WS::ConnectionManager do
  let(:configuration) do
    CoinDCX::Configuration.new.tap do |config|
      config.socket_reconnect_attempts = 2
      config.socket_reconnect_interval = 0.01
      config.socket_heartbeat_interval = 0.5
      config.socket_liveness_timeout = 1.0
    end
  end

  let(:backend) { instance_double("SocketBackend") }
  let(:logger) { instance_double("Logger", info: nil, warn: nil, error: nil) }
  let(:sleeper) { class_double(Kernel, sleep: nil) }
  let(:now) { { value: 100.0 } }
  let(:clock) { -> { now.fetch(:value) } }
  let(:thread_factory) { ->(&_) { nil } }

  subject(:manager) do
    described_class.new(
      configuration: configuration,
      backend: backend,
      logger: logger,
      sleeper: sleeper,
      thread_factory: thread_factory,
      monotonic_clock: clock
    )
  end

  before do
    allow(backend).to receive(:connect)
    allow(backend).to receive(:on)
    allow(backend).to receive(:emit)
    allow(backend).to receive(:disconnect)
  end

  describe "subscription recovery" do
    it "reconnects and resubscribes when heartbeat liveness goes stale" do
      manager.connect
      manager.subscribe(
        type: :public,
        channel_name: "B-BTC_USDT@prices",
        event_name: "price-change",
        payload_builder: -> { { "channelName" => "B-BTC_USDT@prices" } },
        delivery_mode: :at_least_once
      )

      now[:value] += 2.0

      manager.send(:check_liveness!)

      expect(backend).to have_received(:disconnect).once
      expect(backend).to have_received(:connect).twice
      expect(backend).to have_received(:emit).with("join", { "channelName" => "B-BTC_USDT@prices" }).twice
    end

    it "rebuilds private subscription auth payloads after reconnect" do
      payload_sequence = [
        { "channelName" => "coindcx", "authSignature" => "first", "apiKey" => "api-key" },
        { "channelName" => "coindcx", "authSignature" => "second", "apiKey" => "api-key" }
      ]

      manager.connect
      manager.subscribe(
        type: :private,
        channel_name: "coindcx",
        event_name: "order-update",
        payload_builder: -> { payload_sequence.shift },
        delivery_mode: :at_least_once
      )

      now[:value] += 2.0

      manager.send(:check_liveness!)

      expect(backend).to have_received(:emit).with(
        "join",
        { "channelName" => "coindcx", "authSignature" => "first", "apiKey" => "api-key" }
      ).once
      expect(backend).to have_received(:emit).with(
        "join",
        { "channelName" => "coindcx", "authSignature" => "second", "apiKey" => "api-key" }
      ).once
    end
  end

  describe "#alive?" do
    it "reports false after the liveness timeout elapses" do
      manager.connect
      manager.subscribe(
        type: :public,
        channel_name: "B-BTC_USDT@prices",
        event_name: "price-change",
        payload_builder: -> { { "channelName" => "B-BTC_USDT@prices" } },
        delivery_mode: :at_least_once
      )

      expect(manager.alive?).to be(true)

      now[:value] += 2.0

      expect(manager.alive?).to be(false)
    end
  end
end
