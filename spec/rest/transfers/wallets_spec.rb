# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CoinDCX::REST::Transfers::Wallets do
  subject(:resource) { described_class.new(http_client: http_client) }

  let(:http_client) { instance_double(CoinDCX::Transport::HttpClient) }

  before do
    allow(http_client).to receive(:post).and_return({})
  end

  it 'routes transfer operations through authenticated transport calls' do
    resource.transfer(source_wallet_type: 'spot', destination_wallet_type: 'futures', currency_short_name: 'USDT', amount: 1)
    resource.sub_account_transfer(from_account_id: 'A', to_account_id: 'B', currency_short_name: 'USDT', amount: 1)

    expect(http_client).to have_received(:post).with('/exchange/v1/wallets/transfer',
                                                     body: { source_wallet_type: 'spot', destination_wallet_type: 'futures', currency_short_name: 'USDT', amount: 1, timestamp: nil }, auth: true, base: :api, bucket: nil)
    expect(http_client).to have_received(:post).with('/exchange/v1/wallets/sub_account_transfer',
                                                     body: { from_account_id: 'A', to_account_id: 'B', currency_short_name: 'USDT', amount: 1, timestamp: nil }, auth: true, base: :api, bucket: nil)
  end
end
