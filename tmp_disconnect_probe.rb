# frozen_string_literal: true

require_relative "spec/spec_helper"

configuration = CoinDCX::Configuration.new.tap do |c|
  c.api_key = "k"
  c.api_secret = "s"
  c.socket_reconnect_attempts = 2
  c.socket_reconnect_interval = 0.01
end
backend = instance_double("SocketBackend")
sleeper = class_double(Kernel, sleep: nil)
handlers = {}
RSpec::Mocks.with_temporary_scope do
  allow(backend).to receive(:on)
  allow(backend).to receive(:emit)
  allow(backend).to receive(:disconnect)
  allow(backend).to receive(:connect)
  allow(backend).to receive(:on) { |ev, &b| handlers[ev] = b }

  tf = ->(&) { instance_double(Thread) }
  client = CoinDCX::WS::SocketIOClient.new(configuration: configuration, backend: backend, sleeper: sleeper, thread_factory: tf)
  $stdout.puts "connecting"
  client.connect
  $stdout.puts "subscribe"
  client.subscribe_private(event_name: CoinDCX::WS::PrivateChannels::ORDER_UPDATE_EVENT)
  $stdout.puts "disconnect handler"
  handlers.fetch(:disconnect).call("x")
  $stdout.puts "done"
end
