# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CoinDCX::REST::User::Accounts do
  subject(:resource) { described_class.new(http_client: http_client) }

  let(:http_client) { instance_double(CoinDCX::Transport::HttpClient) }

  before do
    allow(http_client).to receive(:post).and_return({})
  end

  it 'routes user account operations through authenticated transport calls' do
    resource.list_balances
    resource.fetch_info

    expect(http_client).to have_received(:post).with('/exchange/v1/users/balances', body: {}, auth: true, base: :api, bucket: nil)
    expect(http_client).to have_received(:post).with('/exchange/v1/users/info', body: {}, auth: true, base: :api, bucket: nil)
  end
end
