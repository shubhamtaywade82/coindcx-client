# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CoinDCX::REST::Margin::Orders do
  subject(:resource) { described_class.new(http_client: http_client) }

  let(:http_client) { instance_double(CoinDCX::Transport::HttpClient) }

  before do
    allow(http_client).to receive(:post).and_return({})
  end

  it 'routes margin operations through authenticated transport calls' do
    resource.create(id: '1')
    resource.list
    resource.fetch(id: '1')
    resource.cancel(id: '1')
    resource.exit_order(id: '1')
    resource.edit_target(id: '1')
    resource.edit_stop_loss(id: '1')
    resource.edit_trailing_stop_loss(id: '1')
    resource.edit_target_order_price(id: '1')
    resource.add_margin(id: '1')
    resource.remove_margin(id: '1')

    expect(http_client).to have_received(:post).with('/exchange/v1/margin/create', body: { id: '1' }, auth: true, base: :api, bucket: nil)
    expect(http_client).to have_received(:post).with('/exchange/v1/margin/fetch_orders', body: {}, auth: true, base: :api, bucket: nil)
    expect(http_client).to have_received(:post).with('/exchange/v1/margin/order', body: { id: '1' }, auth: true, base: :api, bucket: nil)
    expect(http_client).to have_received(:post).with('/exchange/v1/margin/cancel', body: { id: '1' }, auth: true, base: :api, bucket: nil)
    expect(http_client).to have_received(:post).with('/exchange/v1/margin/exit', body: { id: '1' }, auth: true, base: :api, bucket: nil)
    expect(http_client).to have_received(:post).with('/exchange/v1/margin/edit_target', body: { id: '1' }, auth: true, base: :api,
                                                                                        bucket: nil)
    expect(http_client).to have_received(:post).with('/exchange/v1/margin/edit_sl', body: { id: '1' }, auth: true, base: :api, bucket: nil)
    expect(http_client).to have_received(:post).with('/exchange/v1/margin/edit_trailing_sl', body: { id: '1' }, auth: true, base: :api,
                                                                                             bucket: nil)
    expect(http_client).to have_received(:post).with('/exchange/v1/margin/edit_price_of_target_order', body: { id: '1' }, auth: true,
                                                                                                       base: :api, bucket: nil)
    expect(http_client).to have_received(:post).with('/exchange/v1/margin/add_margin', body: { id: '1' }, auth: true, base: :api,
                                                                                       bucket: nil)
    expect(http_client).to have_received(:post).with('/exchange/v1/margin/remove_margin', body: { id: '1' }, auth: true, base: :api,
                                                                                          bucket: nil)
  end
end
