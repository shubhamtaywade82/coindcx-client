# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CoinDCX::REST::Futures::Wallets do
  subject(:resource) { described_class.new(http_client: http_client) }

  let(:http_client) { instance_double(CoinDCX::Transport::HttpClient) }

  before do
    allow(http_client).to receive(:post).and_return({})
    allow(http_client).to receive(:get).and_return({})
  end

  it 'routes futures wallet operations through authenticated transport calls' do
    resource.transfer(transfer_type: 'withdraw', amount: 1, currency_short_name: 'USDT')
    resource.fetch_details
    resource.list_transactions

    expect(http_client).to have_received(:post).with(
      '/exchange/v1/derivatives/futures/wallets/transfer',
      body: { transfer_type: 'withdraw', amount: 1, currency_short_name: 'USDT', timestamp: nil },
      auth: true,
      base: :api,
      bucket: :futures_wallet_transfer
    )
    expect(http_client).to have_received(:get).with(
      '/exchange/v1/derivatives/futures/wallets',
      params: {},
      body: {},
      auth: true,
      base: :api,
      bucket: :futures_wallet_details
    )
    expect(http_client).to have_received(:get).with(
      '/exchange/v1/derivatives/futures/wallets/transactions',
      params: { page: 1, size: 1000 },
      body: {},
      auth: true,
      base: :api,
      bucket: :futures_wallet_transactions
    )
  end
end
