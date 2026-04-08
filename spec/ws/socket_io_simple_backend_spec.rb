# frozen_string_literal: true

require "spec_helper"

RSpec.describe CoinDCX::WS::SocketIOSimpleBackend do
  let(:client_instance) { instance_double("SocketIOClientInstance", connect: true, emit: true, on: true, disconnect: true) }
  let(:client_class) { class_double("SocketIOClientClass", new: client_instance) }
  subject(:backend) { described_class.new(socket_client_class: client_class, connect_options: { EIO: 3 }) }

  before do
    allow(client_instance).to receive(:on)
  end

  it "creates the client, registers listeners, then opens the transport" do
    backend.connect("wss://stream.coindcx.com")
    backend.on("price-change") { |_payload| nil }
    backend.start_transport!
    backend.emit("join", { "channelName" => "coindcx" })

    expect(client_class).to have_received(:new).with("wss://stream.coindcx.com", hash_including(EIO: 3))
    expect(client_instance).to have_received(:on).with("price-change")
    expect(client_instance).to have_received(:connect)
    expect(client_instance).to have_received(:emit).with("join", { "channelName" => "coindcx" })
  end

  it "disconnects the underlying client when present" do
    backend.connect("wss://stream.coindcx.com")
    backend.start_transport!
    backend.disconnect

    expect(client_instance).to have_received(:disconnect)
  end

  it "raises a socket connection error when client construction fails" do
    allow(client_class).to receive(:new).and_raise(StandardError, "boom")

    expect do
      backend.connect("wss://stream.coindcx.com")
    end.to raise_error(CoinDCX::Errors::SocketConnectionError, "boom")
  end
end
