# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CoinDCX::REST::Futures::Orders do
  subject(:resource) { described_class.new(http_client: http_client) }

  let(:http_client) { instance_double(CoinDCX::Transport::HttpClient) }

  before do
    allow(http_client).to receive(:post).and_return({})
  end

  it 'routes futures order operations through authenticated transport calls' do
    resource.list
    resource.create(order: { pair: 'B-BTC_USDT' })
    resource.cancel(id: '1')
    resource.edit(id: '1')

    expect(http_client).to have_received(:post).with('/exchange/v1/derivatives/futures/orders', body: {}, auth: true, base: :api,
                                                                                                bucket: nil)
    expect(http_client).to have_received(:post).with('/exchange/v1/derivatives/futures/orders/create',
                                                     body: { order: { pair: 'B-BTC_USDT' } }, auth: true, base: :api, bucket: nil)
    expect(http_client).to have_received(:post).with('/exchange/v1/derivatives/futures/orders/cancel', body: { id: '1' }, auth: true,
                                                                                                       base: :api, bucket: nil)
    expect(http_client).to have_received(:post).with('/exchange/v1/derivatives/futures/orders/edit', body: { id: '1' }, auth: true,
                                                                                                     base: :api, bucket: nil)
  end
end
