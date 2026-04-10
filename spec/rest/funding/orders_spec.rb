# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CoinDCX::REST::Funding::Orders do
  subject(:resource) { described_class.new(http_client: http_client) }

  let(:http_client) { instance_double(CoinDCX::Transport::HttpClient) }

  before do
    allow(http_client).to receive(:post).and_return({})
  end

  it 'routes funding endpoints through authenticated transport calls' do
    resource.list
    resource.lend(currency: 'USDT', amount: '10')
    resource.settle(id: 'abc123')

    expect(http_client).to have_received(:post).with(
      '/exchange/v1/funding/fetch_orders',
      body: {},
      auth: true,
      base: :api,
      bucket: :funding_fetch_orders
    )

    expect(http_client).to have_received(:post).with(
      '/exchange/v1/funding/lend',
      body: { currency: 'USDT', amount: '10' },
      auth: true,
      base: :api,
      bucket: :funding_lend
    )

    expect(http_client).to have_received(:post).with(
      '/exchange/v1/funding/settle',
      body: { id: 'abc123' },
      auth: true,
      base: :api,
      bucket: :funding_settle
    )
  end
end
