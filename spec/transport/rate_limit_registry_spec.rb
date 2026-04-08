# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CoinDCX::Transport::RateLimitRegistry do
  let(:definitions) { { spot_create_order: { limit: 1, period: 60 } } }
  subject(:registry) { described_class.new(definitions) }

  it 'returns immediately for unknown buckets' do
    expect { registry.acquire(:unknown_bucket) }.not_to raise_error
  end

  it 'sleeps when a bucket is exhausted' do
    allow(registry).to receive(:sleep)
    monotonic_times = [0.0, 5.0, 61.0]
    allow(registry).to receive(:monotonic_time) { monotonic_times.shift }

    registry.acquire(:spot_create_order)
    registry.acquire(:spot_create_order)

    expect(registry).to have_received(:sleep).with(55.0).once
  end
end
