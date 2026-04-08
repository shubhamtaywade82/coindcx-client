# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CoinDCX::REST::Spot::Orders do
  subject(:resource) { described_class.new(http_client: http_client) }

  let(:http_client) { instance_double(CoinDCX::Transport::HttpClient) }

  before do
    allow(http_client).to receive(:post).and_return({})
  end

  it 'routes all spot order operations through authenticated transport calls' do
    resource.create(market: 'SNTBTC')
    resource.create_many(orders: [{ market: 'SNTBTC' }])
    resource.fetch_status(id: '1')
    resource.fetch_statuses(ids: ['1'])
    resource.list_active
    resource.count_active
    resource.list_trade_history
    resource.cancel(id: '1')
    resource.cancel_many(ids: ['1'])
    resource.cancel_all
    resource.edit_price(id: '1')

    expect(http_client).to have_received(:post).with('/exchange/v1/orders/create', body: { market: 'SNTBTC' }, auth: true, base: :api,
                                                                                   bucket: :spot_create_order)
    expect(http_client).to have_received(:post).with('/exchange/v1/orders/create_multiple', body: { orders: [{ market: 'SNTBTC' }] },
                                                                                            auth: true, base: :api, bucket: :spot_create_order_multiple)
    expect(http_client).to have_received(:post).with('/exchange/v1/orders/status', body: { id: '1' }, auth: true, base: :api,
                                                                                   bucket: :spot_order_status)
    expect(http_client).to have_received(:post).with('/exchange/v1/orders/status_multiple', body: { ids: ['1'] }, auth: true, base: :api,
                                                                                            bucket: :spot_order_status_multiple)
    expect(http_client).to have_received(:post).with('/exchange/v1/orders/active_orders', body: {}, auth: true, base: :api,
                                                                                          bucket: :spot_active_order)
    expect(http_client).to have_received(:post).with('/exchange/v1/orders/active_orders_count', body: {}, auth: true, base: :api,
                                                                                                bucket: nil)
    expect(http_client).to have_received(:post).with('/exchange/v1/orders/trade_history', body: {}, auth: true, base: :api, bucket: nil)
    expect(http_client).to have_received(:post).with('/exchange/v1/orders/cancel', body: { id: '1' }, auth: true, base: :api,
                                                                                   bucket: :spot_cancel_order)
    expect(http_client).to have_received(:post).with('/exchange/v1/orders/cancel_by_ids', body: { ids: ['1'] }, auth: true, base: :api,
                                                                                          bucket: :spot_cancel_multiple_by_id)
    expect(http_client).to have_received(:post).with('/exchange/v1/orders/cancel_all', body: {}, auth: true, base: :api,
                                                                                       bucket: :spot_cancel_all)
    expect(http_client).to have_received(:post).with('/exchange/v1/orders/edit', body: { id: '1' }, auth: true, base: :api,
                                                                                 bucket: :spot_edit_price)
  end
end
