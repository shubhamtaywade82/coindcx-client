# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CoinDCX::REST::Futures::MarketData do
  subject(:resource) { described_class.new(http_client: http_client) }

  let(:http_client) { instance_double(CoinDCX::Transport::HttpClient) }

  before do
    allow(http_client).to receive(:get).and_return({})
  end

  it 'routes futures market data requests to the expected endpoints' do
    resource.list_active_instruments
    resource.fetch_instrument(pair: 'B-BTC_USDT', margin_currency_short_name: 'USDT')
    resource.list_trades(pair: 'B-BTC_USDT')
    resource.fetch_order_book(instrument: 'B-BTC_USDT', depth: 50)
    resource.list_candlesticks(pair: 'B-BTC_USDT', from: 1, to: 2, resolution: '1D')
    resource.current_prices
    resource.stats(pair: 'B-BTC_USDT')
    resource.conversions

    expect(http_client).to have_received(:get).with('/exchange/v1/derivatives/futures/data/active_instruments',
                                                    params: { 'margin_currency_short_name[]': ['USDT'] }, body: {}, auth: false, base: :api, bucket: nil)
    expect(http_client).to have_received(:get).with('/exchange/v1/derivatives/futures/data/instrument',
                                                    params: { pair: 'B-BTC_USDT', margin_currency_short_name: 'USDT' }, body: {}, auth: true,
                                                    base: :api, bucket: :futures_instrument_detail)
    expect(http_client).to have_received(:get).with('/exchange/v1/derivatives/futures/data/trades', params: { pair: 'B-BTC_USDT' }, body: {},
                                                                                                    auth: false, base: :api, bucket: nil)
    expect(http_client).to have_received(:get).with('/market_data/v3/orderbook/B-BTC_USDT-futures/50', params: {}, body: {}, auth: false,
                                                                                                       base: :public, bucket: nil)
    expect(http_client).to have_received(:get).with('/market_data/candlesticks',
                                                    params: { pair: 'B-BTC_USDT', from: 1, to: 2, resolution: '1D', pcode: 'f' }, body: {},
                                                    auth: false, base: :public, bucket: nil)
    expect(http_client).to have_received(:get).with('/market_data/v3/current_prices/futures/rt', params: {}, body: {}, auth: false,
                                                                                                 base: :public, bucket: :public_market_data)
    expect(http_client).to have_received(:get).with('/api/v1/derivatives/futures/data/stats', params: { pair: 'B-BTC_USDT' }, body: {},
                                                                                              auth: false, base: :api, bucket: nil)
    expect(http_client).to have_received(:get).with('/api/v1/derivatives/futures/data/conversions', params: {}, body: {}, auth: false,
                                                                                                    base: :api, bucket: nil)
  end

  it 'rejects unsupported order book depths' do
    expect do
      resource.fetch_order_book(instrument: 'B-BTC_USDT', depth: 5)
    end.to raise_error(CoinDCX::Errors::ValidationError)
  end
end
