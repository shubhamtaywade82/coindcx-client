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

  before do
    allow(backend).to receive(:on)
    allow(backend).to receive(:emit)
    allow(backend).to receive(:disconnect)
  end

  describe "#subscribe_public" do
    it "rejoins subscriptions after a reconnect event" do
      handlers = {}
      allow(backend).to receive(:connect)
      allow(backend).to receive(:on) do |event_name, &block|
        handlers[event_name] = block
      end

      client = described_class.new(configuration: configuration, backend: backend, sleeper: sleeper)
      client.connect
      client.subscribe_public(channel_name: "B-BTC_USDT@prices", event_name: "price-change")

      expect(backend).to have_received(:emit).with("join", { "channelName" => "B-BTC_USDT@prices" }).once

      handlers.fetch(:connect).call

      expect(backend).to have_received(:emit).with("join", { "channelName" => "B-BTC_USDT@prices" }).twice
    end
  end

  describe "#subscribe_private" do
    it "renews private channel auth payloads after reconnect" do
      handlers = {}
      allow(backend).to receive(:connect)
      allow(backend).to receive(:on) do |event_name, &block|
        handlers[event_name] = block
      end

      client = described_class.new(configuration: configuration, backend: backend, sleeper: sleeper)
      client.connect
      client.subscribe_private(event_name: CoinDCX::WS::PrivateChannels::ORDER_UPDATE_EVENT)

      first_payload = nil
      second_payload = nil

      expect(backend).to have_received(:emit).with("join", kind_of(Hash)).once
      first_payload = RSpec::Mocks.space.proxy_for(backend).messages_arg_list
        .select { |args| args.first == "join" }
        .first
        .last

      allow(client).to receive(:join_payload).and_call_original
      allow(client).to receive(:join_payload)
        .with(type: :private, channel_name: CoinDCX::WS::PrivateChannels::DEFAULT_CHANNEL_NAME)
        .and_wrap_original do |original, *args, **kwargs|
          payload = original.call(*args, **kwargs)
          payload.merge("authSignature" => "#{payload.fetch('authSignature')}-renewed")
        end

      handlers.fetch(:disconnect).call("network_lost")

      join_payloads = RSpec::Mocks.space.proxy_for(backend).messages_arg_list
        .select { |args| args.first == "join" }
        .map(&:last)
      second_payload = join_payloads.last

      expect(second_payload).not_to eq(first_payload)
      expect(second_payload.fetch("authSignature")).to end_with("-renewed")
    end

    it "does not reconnect a quiet private subscription" do
      now = 100.0
      handlers = {}
      clock = -> { now }

      allow(backend).to receive(:connect)
      allow(backend).to receive(:on) do |event_name, &block|
        handlers[event_name] = block
      end

      threads = []
      thread_factory = lambda do |&block|
        threads << block
        instance_double("Thread")
      end

      client = described_class.new(
        configuration: configuration,
        backend: backend,
        sleeper: sleeper,
        thread_factory: thread_factory,
        monotonic_clock: clock
      )
      client.connect
      client.subscribe_private(event_name: CoinDCX::WS::PrivateChannels::ORDER_UPDATE_EVENT)

      now += 2.0
      threads.first.call

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

        true
      end

      client = described_class.new(configuration: configuration, backend: backend, sleeper: sleeper)
      client.connect

      expect(backend).to have_received(:connect).twice
      expect(sleeper).to have_received(:sleep).with(0.01)
    end

    it "reconnects and resubscribes after a disconnect event" do
      handlers = {}
      allow(backend).to receive(:connect)
      allow(backend).to receive(:on) do |event_name, &block|
        handlers[event_name] = block
      end

      client = described_class.new(configuration: configuration, backend: backend, sleeper: sleeper)
      client.connect
      client.subscribe_public(channel_name: "B-BTC_USDT@prices", event_name: "price-change")

      handlers.fetch(:disconnect).call("network_lost")

      expect(backend).to have_received(:connect).twice
      expect(backend).to have_received(:emit).with("join", { "channelName" => "B-BTC_USDT@prices" }).at_least(:twice)
      expect(sleeper).to have_received(:sleep).with(0.01)
    end
  end

  describe "heartbeat liveness" do
    it "reconnects after a stale subscription" do
      now = 100.0
      handlers = {}
      clock = -> { now }

      allow(backend).to receive(:connect)
      allow(backend).to receive(:on) do |event_name, &block|
        handlers[event_name] = block
      end

      threads = []
      thread_factory = lambda do |&block|
        threads << block
        instance_double("Thread")
      end

      client = described_class.new(
        configuration: configuration,
        backend: backend,
        sleeper: sleeper,
        thread_factory: thread_factory,
        monotonic_clock: clock
      )
      client.connect
      client.subscribe_public(channel_name: "B-BTC_USDT@prices", event_name: "price-change")

      now += 2.0
      threads.first.call

      expect(backend).to have_received(:connect).twice
      expect(backend).to have_received(:emit).with("join", { "channelName" => "B-BTC_USDT@prices" }).at_least(:twice)
    end
  end
end
