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
  let(:thread_factory) { ->(&_) {} }

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
      # Heartbeat liveness only runs when a public subscription exists; include one so stale
      # connection recovery exercises resubscribe (and fresh private join payloads).
      manager.subscribe(
        type: :public,
        channel_name: "B-BTC_USDT@prices",
        event_name: "price-change",
        payload_builder: -> { { "channelName" => "B-BTC_USDT@prices" } },
        delivery_mode: :at_least_once
      )
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
        { "channelName" => "B-BTC_USDT@prices" }
      ).twice
      expect(backend).to have_received(:emit).with(
        "join",
        { "channelName" => "coindcx", "authSignature" => "first", "apiKey" => "api-key" }
      ).once
      expect(backend).to have_received(:emit).with(
        "join",
        { "channelName" => "coindcx", "authSignature" => "second", "apiKey" => "api-key" }
      ).once
    end

    it "does not reconnect a quiet private subscription just because no payload arrived" do
      manager.connect
      manager.subscribe(
        type: :private,
        channel_name: "coindcx",
        event_name: "order-update",
        payload_builder: -> { { "channelName" => "coindcx", "authSignature" => "first", "apiKey" => "api-key" } },
        delivery_mode: :at_least_once
      )

      now[:value] += 2.0

      manager.send(:check_liveness!)

      expect(backend).to have_received(:connect).once
      expect(backend).not_to have_received(:disconnect)
    end
  end

  describe "socket.io listener binding (event_emitter uses instance_exec on the client)" do
    let(:captured_listeners) { {} }

    before do
      allow(backend).to receive(:on) do |event, &block|
        captured_listeners[event] = block
      end
    end

    it "runs disconnect without NameError when the block executes with the socket as self" do
      manager.connect
      manager.define_singleton_method(:reconnect) { nil }

      disconnect_block = captured_listeners[:disconnect]
      expect(disconnect_block).to be_a(Proc)

      bogus_socket = Object.new
      expect { bogus_socket.instance_exec(&disconnect_block) }.not_to raise_error
    end

    it "delivers public payloads to registered handlers when the bridge runs under instance_exec" do
      received = []
      manager.connect
      manager.on("price-change") { |payload| received << payload }
      manager.subscribe(
        type: :public,
        channel_name: "B-BTC_USDT@prices",
        event_name: "price-change",
        payload_builder: -> { { "channelName" => "B-BTC_USDT@prices" } },
        delivery_mode: :at_least_once
      )

      bridge = captured_listeners["price-change"]
      expect(bridge).to be_a(Proc)

      tick = { "p" => "1.0" }
      Object.new.instance_exec(tick, &bridge)

      expect(received).to eq([tick])
    end

    it "coalesces Socket.IO multi-arg frames into the hash payload for handlers" do
      received = []
      manager.connect
      manager.on("new-trade") { |payload| received << payload }
      manager.subscribe(
        type: :public,
        channel_name: "B-BTC_USDT@trades-futures",
        event_name: "new-trade",
        payload_builder: -> { { "channelName" => "B-BTC_USDT@trades-futures" } },
        delivery_mode: :at_least_once
      )

      bridge = captured_listeners["new-trade"]
      channel = "B-BTC_USDT@trades-futures"
      trade = { "p" => "2.0", "s" => "BTCUSDT" }
      Object.new.instance_exec(channel, trade, &bridge)

      expect(received).to eq([trade])
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
