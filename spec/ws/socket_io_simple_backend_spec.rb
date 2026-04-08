# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CoinDCX::WS::SocketIOSimpleBackend do
  let(:socket) { instance_double('SocketIoSocket', emit: true, close: true) }
  let(:socket_factory) { class_double('SocketFactory') }
  subject(:backend) { described_class.new(socket_factory: socket_factory) }

  before do
    allow(socket).to receive(:on)
  end

  it 'delegates connect, emit, on, and disconnect to the socket client' do
    allow(socket_factory).to receive(:connect).with('wss://stream.coindcx.com', hash_including(EIO: 4)).and_return(socket)

    backend.connect('wss://stream.coindcx.com')
    backend.emit('join', { 'channelName' => 'coindcx' })
    backend.on('price-change') { |_payload| nil }
    backend.disconnect

    expect(socket).to have_received(:emit).with('join', { 'channelName' => 'coindcx' })
    expect(socket).to have_received(:on).with('price-change')
    expect(socket).to have_received(:close)
  end

  it 'raises a socket connection error when connect fails' do
    allow(socket_factory).to receive(:connect).and_raise(StandardError, 'boom')

    expect do
      backend.connect('wss://stream.coindcx.com')
    end.to raise_error(CoinDCX::Errors::SocketConnectionError, 'boom')
  end
end
