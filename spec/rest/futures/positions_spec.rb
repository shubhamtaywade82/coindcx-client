# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CoinDCX::REST::Futures::Positions do
  subject(:resource) { described_class.new(http_client: http_client) }

  let(:http_client) { instance_double(CoinDCX::Transport::HttpClient) }

  before do
    allow(http_client).to receive(:post).and_return({})
  end

  it 'routes futures position operations through authenticated transport calls' do
    resource.list
    resource.update_leverage(id: '1')
    resource.add_margin(id: '1')
    resource.remove_margin(id: '1')
    resource.cancel_all_open_orders(id: '1')
    resource.cancel_all_open_orders_for_position(id: '1')
    resource.exit_position(id: '1')
    resource.create_take_profit_stop_loss(id: '1')
    resource.list_transactions
    resource.fetch_cross_margin_details
    resource.update_margin_type(id: '1')

    expect(http_client).to have_received(:post).with('/exchange/v1/derivatives/futures/positions', body: {}, auth: true, base: :api,
                                                                                                   bucket: :futures_positions_list)
    expect(http_client).to have_received(:post).with('/exchange/v1/derivatives/futures/positions/update_leverage', body: { id: '1' },
                                                                                                                   auth: true, base: :api, bucket: :futures_positions_update_leverage)
    expect(http_client).to have_received(:post).with('/exchange/v1/derivatives/futures/positions/add_margin', body: { id: '1' },
                                                                                                              auth: true, base: :api, bucket: :futures_positions_add_margin)
    expect(http_client).to have_received(:post).with('/exchange/v1/derivatives/futures/positions/remove_margin', body: { id: '1' },
                                                                                                                 auth: true, base: :api, bucket: :futures_positions_remove_margin)
    expect(http_client).to have_received(:post).with('/exchange/v1/derivatives/futures/positions/cancel_all_open_orders',
                                                     body: { id: '1' }, auth: true, base: :api, bucket: :futures_positions_cancel_all_open_orders)
    expect(http_client).to have_received(:post).with('/exchange/v1/derivatives/futures/positions/cancel_all_open_orders_for_position',
                                                     body: { id: '1' }, auth: true, base: :api, bucket: :futures_positions_cancel_all_open_orders_for_position)
    expect(http_client).to have_received(:post).with('/exchange/v1/derivatives/futures/positions/exit', body: { id: '1' }, auth: true,
                                                                                                        base: :api, bucket: :futures_positions_exit)
    expect(http_client).to have_received(:post).with('/exchange/v1/derivatives/futures/positions/create_tpsl', body: { id: '1' },
                                                                                                               auth: true, base: :api, bucket: :futures_positions_create_tpsl)
    expect(http_client).to have_received(:post).with('/exchange/v1/derivatives/futures/positions/transactions', body: {}, auth: true,
                                                                                                                base: :api, bucket: :futures_positions_transactions)
    expect(http_client).to have_received(:post).with('/exchange/v1/derivatives/futures/positions/cross_margin_details', body: {},
                                                                                                                        auth: true, base: :api, bucket: :futures_positions_cross_margin_details)
    expect(http_client).to have_received(:post).with('/exchange/v1/derivatives/futures/positions/margin_type', body: { id: '1' },
                                                                                                               auth: true, base: :api, bucket: :futures_positions_margin_type)
  end
end
