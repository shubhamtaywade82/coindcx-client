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
  let(:backend_listeners) { {} }

  # Zero-jitter randomizer keeps sleep assertions deterministic.
  let(:randomizer) { -> { 0.0 } }

  subject(:manager) do
    described_class.new(
      configuration: configuration,
      backend: backend,
      logger: logger,
      sleeper: sleeper,
      thread_factory: thread_factory,
      monotonic_clock: clock,
      randomizer: randomizer
    )
  end

  before do
    allow(backend).to receive(:connect)
    allow(backend).to receive(:start_transport!)
    allow(backend).to receive(:on) do |event, &block|
      backend_listeners[event] = block
    end
    allow(backend).to receive(:emit)
    allow(backend).to receive(:disconnect)
  end

  def fire_engine_io_open!
    backend_listeners[:connect]&.call
  end

  describe "subscription recovery" do
    it "reconnects and resubscribes when heartbeat liveness goes stale" do
      manager.connect
      fire_engine_io_open!
      manager.subscribe(
        type: :public,
        channel_name: "B-BTC_USDT@prices",
        event_name: "price-change",
        payload_builder: -> { { "channelName" => "B-BTC_USDT@prices" } },
        delivery_mode: :at_least_once
      )

      now[:value] += 2.0

      manager.send(:check_liveness!)

      fire_engine_io_open!

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
      fire_engine_io_open!
      # Include a public subscription alongside private so both reconnect paths are covered.
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

      fire_engine_io_open!

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

    it "reconnects a private-only subscription that exceeds the liveness timeout" do
      manager.connect
      fire_engine_io_open!
      manager.subscribe(
        type: :private,
        channel_name: "coindcx",
        event_name: "order-update",
        payload_builder: -> { { "channelName" => "coindcx", "authSignature" => "fresh", "apiKey" => "api-key" } },
        delivery_mode: :at_least_once
      )

      now[:value] += 2.0  # exceed liveness_timeout of 1.0s

      manager.send(:check_liveness!)
      fire_engine_io_open!

      expect(backend).to have_received(:disconnect).once
      expect(backend).to have_received(:connect).twice
      expect(backend).to have_received(:emit).with(
        "join",
        { "channelName" => "coindcx", "authSignature" => "fresh", "apiKey" => "api-key" }
      ).twice
    end

    it "does not reconnect a private subscription still within the liveness window" do
      manager.connect
      fire_engine_io_open!
      manager.subscribe(
        type: :private,
        channel_name: "coindcx",
        event_name: "order-update",
        payload_builder: -> { { "channelName" => "coindcx", "authSignature" => "first", "apiKey" => "api-key" } },
        delivery_mode: :at_least_once
      )

      now[:value] += 0.5  # well within liveness_timeout of 1.0s

      manager.send(:check_liveness!)

      expect(backend).to have_received(:connect).once
      expect(backend).not_to have_received(:disconnect)
    end
  end

  describe "socket.io listener binding (event_emitter uses instance_exec on the client)" do
    it "runs disconnect without NameError when the block executes with the socket as self" do
      manager.connect
      manager.define_singleton_method(:reconnect) { nil }

      disconnect_block = backend_listeners[:disconnect]
      expect(disconnect_block).to be_a(Proc)

      bogus_socket = Object.new
      expect { bogus_socket.instance_exec(&disconnect_block) }.not_to raise_error
    end

    it "delivers public payloads to registered handlers when the bridge runs under instance_exec" do
      received = []
      manager.connect
      fire_engine_io_open!
      manager.on("price-change") { |payload| received << payload }
      manager.subscribe(
        type: :public,
        channel_name: "B-BTC_USDT@prices",
        event_name: "price-change",
        payload_builder: -> { { "channelName" => "B-BTC_USDT@prices" } },
        delivery_mode: :at_least_once
      )

      bridge = backend_listeners["price-change"]
      expect(bridge).to be_a(Proc)

      tick = { "p" => "1.0" }
      Object.new.instance_exec(tick, &bridge)

      expect(received).to eq([tick])
    end

    it "coalesces Socket.IO multi-arg frames into the hash payload for handlers" do
      received = []
      manager.connect
      fire_engine_io_open!
      manager.on("new-trade") { |payload| received << payload }
      manager.subscribe(
        type: :public,
        channel_name: "B-BTC_USDT@trades-futures",
        event_name: "new-trade",
        payload_builder: -> { { "channelName" => "B-BTC_USDT@trades-futures" } },
        delivery_mode: :at_least_once
      )

      bridge = backend_listeners["new-trade"]
      channel = "B-BTC_USDT@trades-futures"
      trade = { "p" => "2.0", "s" => "BTCUSDT" }
      Object.new.instance_exec(channel, trade, &bridge)

      expect(received).to eq([trade])
    end

    it "unwraps CoinDCX envelope hashes whose data field is a JSON string" do
      received = []
      manager.connect
      fire_engine_io_open!
      manager.on("price-change") { |payload| received << payload }
      manager.subscribe(
        type: :public,
        channel_name: "B-BTC_USDT@prices-futures",
        event_name: "price-change",
        payload_builder: -> { { "channelName" => "B-BTC_USDT@prices-futures" } },
        delivery_mode: :at_least_once
      )

      bridge = backend_listeners["price-change"]
      envelope = {
        "event" => "price-change",
        "data" => "{\"T\":1775667421370,\"p\":\"71585.4\",\"pr\":\"f\"}"
      }
      Object.new.instance_exec(envelope, &bridge)

      expect(received.size).to eq(1)
      expect(received.first["p"]).to eq("71585.4")
      expect(received.first).not_to have_key("data")
    end
  end

  describe "#alive?" do
    it "reports false after the liveness timeout elapses" do
      manager.connect
      fire_engine_io_open!
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

  describe "reconnect backoff" do
    it "applies exponential backoff bounded by MAX_BACKOFF_INTERVAL with zero jitter" do
      base = configuration.socket_reconnect_interval # 0.01

      # attempts 1..3 → intervals 0.01, 0.02, 0.04 (well under ceiling)
      expect(manager.send(:reconnect_interval, 1)).to eq(base * 1)
      expect(manager.send(:reconnect_interval, 2)).to eq(base * 2)
      expect(manager.send(:reconnect_interval, 3)).to eq(base * 4)
    end

    it "caps the backoff at MAX_BACKOFF_INTERVAL" do
      configuration.socket_reconnect_interval = 1.0

      # 2^30 would be enormous; ceiling at 30s
      result = manager.send(:reconnect_interval, 30)
      expect(result).to eq(CoinDCX::WS::ConnectionManager::MAX_BACKOFF_INTERVAL)
    end

    it "adds jitter proportional to the base interval" do
      jitter_randomizer = -> { 1.0 } # max jitter: base * 0.25
      jittery_manager = described_class.new(
        configuration: configuration,
        backend: backend,
        logger: logger,
        sleeper: sleeper,
        thread_factory: thread_factory,
        monotonic_clock: clock,
        randomizer: jitter_randomizer
      )

      base = configuration.socket_reconnect_interval
      expected = base + (base * 0.25)
      expect(jittery_manager.send(:reconnect_interval, 1)).to be_within(0.0001).of(expected)
    end
  end

  describe "state transition guards" do
    it "raises SocketStateError on an illegal transition" do
      # :disconnected may only go to :connecting or :reconnecting
      expect do
        manager.send(:state).transition_to(:subscribed)
      end.to raise_error(CoinDCX::Errors::SocketStateError, /disconnected.*subscribed/)
    end

    it "is a no-op when transitioning to the current state" do
      expect { manager.send(:state).transition_to(:disconnected) }.not_to raise_error
    end

    it "allows :failed state after exhausting reconnect retries" do
      allow(backend).to receive(:connect).and_raise(CoinDCX::Errors::SocketConnectionError, "refused")

      expect { manager.connect }.to raise_error(CoinDCX::Errors::SocketConnectionError)
      expect(manager.send(:state).current).to eq(:failed)
    end

    it "raises SocketStateError when the transition map is violated" do
      state = CoinDCX::WS::ConnectionState.new
      state.transition_to(:connecting) # disconnected → connecting ✓
      state.transition_to(:authenticated) # connecting → authenticated ✓

      expect do
        state.transition_to(:connecting)  # authenticated → connecting ✗
      end.to raise_error(CoinDCX::Errors::SocketStateError)
    end
  end

  describe "#disconnect" do
    it "is idempotent — calling disconnect twice does not raise" do
      manager.connect
      fire_engine_io_open!

      expect { manager.disconnect }.not_to raise_error
      expect { manager.disconnect }.not_to raise_error
    end
  end
end
