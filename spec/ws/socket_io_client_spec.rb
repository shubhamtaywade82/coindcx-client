# frozen_string_literal: true

require "spec_helper"

RSpec.describe CoinDCX::WS::SocketIOClient do
  let(:configuration) do
    CoinDCX::Configuration.new.tap do |config|
      config.api_key = "api-key"
      config.api_secret = "api-secret"
      config.socket_reconnect_attempts = 2
      config.socket_reconnect_interval = 0.01
      config.socket_heartbeat_interval = 0.5
      config.socket_liveness_timeout = 1.0
    end
  end

  let(:backend) { instance_double("SocketBackend") }
  let(:sleeper) { class_double(Kernel, sleep: nil) }
  # Stubbed sleeper.sleep returns immediately; a real heartbeat Thread would tight-loop on the GVL and
  # starve examples. Capture the loop body; drive liveness via ConnectionManager#check_liveness! in specs.
  let(:captured_heartbeat_blocks) { [] }
  let(:thread_factory_without_run) do
    lambda do |&block|
      captured_heartbeat_blocks << block
      instance_double(Thread, join: nil, kill: nil)
    end
  end

  before do
    allow(backend).to receive(:connect)
    allow(backend).to receive(:start_transport!)
    allow(backend).to receive(:on)
    allow(backend).to receive(:emit)
    allow(backend).to receive(:disconnect)
  end

  describe "#leave_channel" do
    it "emits leave with a validated channelName" do
      client = described_class.new(
        configuration: configuration,
        backend: backend,
        sleeper: sleeper,
        thread_factory: thread_factory_without_run
      )
      client.connect
      client.leave_channel(channel_name: "B-BTC_USDT@prices")

      expect(backend).to have_received(:emit).with(
        "leave",
        { "channelName" => "B-BTC_USDT@prices" }
      )
    end
  end

  describe "#subscribe_public" do
    it "emits join after Engine.IO open (:connect), and resubscribes on each open" do
      handlers = {}
      allow(backend).to receive(:on) do |event_name, &block|
        handlers[event_name] = block
      end

      client = described_class.new(
        configuration: configuration,
        backend: backend,
        sleeper: sleeper,
        thread_factory: thread_factory_without_run
      )
      client.connect
      client.subscribe_public(channel_name: "B-BTC_USDT@prices", event_name: "price-change")

      expect(backend).not_to have_received(:emit).with("join", { "channelName" => "B-BTC_USDT@prices" })

      handlers.fetch(:connect).call

      expect(backend).to have_received(:emit).with("join", { "channelName" => "B-BTC_USDT@prices" }).once

      handlers.fetch(:connect).call

      expect(backend).to have_received(:emit).with("join", { "channelName" => "B-BTC_USDT@prices" }).twice
    end
  end

  describe "#subscribe_private" do
    it "renews private channel auth payloads after reconnect" do
      handlers = {}
      captured_join_payloads = []
      allow(backend).to receive(:on) do |event_name, &block|
        handlers[event_name] = block
      end
      allow(backend).to receive(:emit) do |op, payload|
        captured_join_payloads << payload if op == "join"
      end

      client = described_class.new(
        configuration: configuration,
        backend: backend,
        sleeper: sleeper,
        thread_factory: thread_factory_without_run
      )
      client.connect
      handlers.fetch(:connect).call
      client.subscribe_private(event_name: CoinDCX::WS::PrivateChannels::ORDER_UPDATE_EVENT)

      expect(captured_join_payloads.size).to eq(1)
      first_payload = captured_join_payloads.first

      allow(client).to receive(:join_payload).and_call_original
      allow(client).to receive(:join_payload)
        .with(type: :private, channel_name: CoinDCX::WS::PrivateChannels::DEFAULT_CHANNEL_NAME)
        .and_wrap_original do |original, *args, **kwargs|
          payload = original.call(*args, **kwargs)
          payload.merge("authSignature" => "#{payload.fetch('authSignature')}-renewed")
        end

      handlers.fetch(:disconnect).call("network_lost")
      handlers[:connect]&.call

      second_payload = captured_join_payloads.last

      expect(second_payload).not_to eq(first_payload)
      expect(second_payload.fetch("authSignature")).to end_with("-renewed")
    end

    it "does not reconnect a private subscription still within the liveness window" do
      now = 100.0
      handlers = {}
      clock = -> { now }

      allow(backend).to receive(:on) do |event_name, &block|
        handlers[event_name] = block
      end

      client = described_class.new(
        configuration: configuration,
        backend: backend,
        sleeper: sleeper,
        thread_factory: thread_factory_without_run,
        monotonic_clock: clock
      )
      client.connect
      handlers.fetch(:connect).call
      client.subscribe_private(event_name: CoinDCX::WS::PrivateChannels::ORDER_UPDATE_EVENT)

      # Advance clock but stay inside the liveness timeout — no reconnect expected.
      now += 0.5
      client.send(:connection_manager).send(:check_liveness!)

      expect(backend).to have_received(:connect).once
      expect(client.alive?).to be(true)
    end
  end

  describe "#connect" do
    it "retries socket connection failures with backoff" do
      allow(backend).to receive(:connect) do
        @connect_attempts ||= 0
        @connect_attempts += 1
        raise CoinDCX::Errors::SocketConnectionError, "temporary failure" if @connect_attempts == 1

        self
      end

      client = described_class.new(
        configuration: configuration,
        backend: backend,
        sleeper: sleeper,
        thread_factory: thread_factory_without_run,
        randomizer: -> { 0.0 }  # zero jitter → deterministic sleep value
      )
      client.connect

      expect(backend).to have_received(:connect).twice
      expect(sleeper).to have_received(:sleep).with(0.01)
    end

    it "reconnects and resubscribes after a disconnect event" do
      handlers = {}
      allow(backend).to receive(:on) do |event_name, &block|
        handlers[event_name] = block
      end

      client = described_class.new(
        configuration: configuration,
        backend: backend,
        sleeper: sleeper,
        thread_factory: thread_factory_without_run
      )
      client.connect
      handlers.fetch(:connect).call
      client.subscribe_public(channel_name: "B-BTC_USDT@prices", event_name: "price-change")

      handlers.fetch(:disconnect).call("network_lost")
      handlers[:connect]&.call

      expect(backend).to have_received(:connect).twice
      expect(backend).to have_received(:emit).with("join", { "channelName" => "B-BTC_USDT@prices" }).at_least(:twice)
    end
  end

  describe "heartbeat liveness" do
    it "reconnects after a stale subscription" do
      now = 100.0
      handlers = {}
      clock = -> { now }

      allow(backend).to receive(:on) do |event_name, &block|
        handlers[event_name] = block
      end

      client = described_class.new(
        configuration: configuration,
        backend: backend,
        sleeper: sleeper,
        thread_factory: thread_factory_without_run,
        monotonic_clock: clock
      )
      client.connect
      handlers.fetch(:connect).call
      client.subscribe_public(channel_name: "B-BTC_USDT@prices", event_name: "price-change")

      now += 2.0
      client.send(:connection_manager).send(:check_liveness!)
      handlers[:connect]&.call

      expect(backend).to have_received(:connect).twice
      expect(backend).to have_received(:emit).with("join", { "channelName" => "B-BTC_USDT@prices" }).at_least(:twice)
    end
  end
end
