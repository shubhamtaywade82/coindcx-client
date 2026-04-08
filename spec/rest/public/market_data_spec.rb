# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CoinDCX::REST::Public::MarketData do
  subject(:resource) { described_class.new(http_client: http_client) }

  let(:http_client) { instance_double(CoinDCX::Transport::HttpClient) }

  it 'requests public market endpoints through the transport' do
    allow(http_client).to receive(:get).and_return([])

    resource.list_tickers
    resource.list_markets
    resource.list_market_details
    resource.list_trades(pair: 'B-BTC_USDT', limit: 10)
    resource.fetch_order_book(pair: 'B-BTC_USDT')
    resource.list_candles(pair: 'B-BTC_USDT', interval: '1m', start_time: 1, end_time: 2, limit: 3)

    expect(http_client).to have_received(:get).with('/exchange/ticker', params: {}, auth: false, base: :api, bucket: nil)
    expect(http_client).to have_received(:get).with('/exchange/v1/markets', params: {}, auth: false, base: :api, bucket: nil)
    expect(http_client).to have_received(:get).with('/exchange/v1/markets_details', params: {}, auth: false, base: :api, bucket: nil)
    expect(http_client).to have_received(:get).with('/market_data/trade_history', params: { pair: 'B-BTC_USDT', limit: 10 }, auth: false,
                                                                                  base: :public, bucket: nil)
    expect(http_client).to have_received(:get).with('/market_data/orderbook', params: { pair: 'B-BTC_USDT' }, auth: false, base: :public,
                                                                              bucket: nil)
    expect(http_client).to have_received(:get).with('/market_data/candles',
                                                    params: { pair: 'B-BTC_USDT', interval: '1m', startTime: 1, endTime: 2, limit: 3 }, auth: false, base: :public, bucket: nil)
  end
end
