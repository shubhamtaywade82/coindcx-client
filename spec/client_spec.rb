# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CoinDCX::Client do
  subject(:client) { described_class.new(configuration: configuration) }

  let(:configuration) { CoinDCX::Configuration.new }

  it 'builds facades for each API namespace' do
    expect(client.public).to be_a(CoinDCX::REST::Public::Facade)
    expect(client.spot).to be_a(CoinDCX::REST::Spot::Facade)
    expect(client.margin).to be_a(CoinDCX::REST::Margin::Facade)
    expect(client.user).to be_a(CoinDCX::REST::User::Facade)
    expect(client.transfers).to be_a(CoinDCX::REST::Transfers::Facade)
    expect(client.futures).to be_a(CoinDCX::REST::Futures::Facade)
    expect(client.funding).to be_a(CoinDCX::REST::Funding::Facade)
  end
end
