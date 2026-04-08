# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CoinDCX::Transport::RateLimitRegistry do
  let(:definitions) { { spot_create_order: { limit: 1, period: 60 } } }
  subject(:registry) { described_class.new(definitions) }

  it 'returns immediately for unknown buckets when throttling is optional' do
    expect { registry.throttle(:unknown_bucket) }.not_to raise_error
  end

  it 'raises when a required bucket has no rate limit definition' do
    expect { registry.throttle(:unknown_bucket, required: true) }
      .to raise_error(CoinDCX::Errors::ConfigurationError, 'missing rate limit definition for unknown_bucket')
  end

  it 'sleeps when a bucket is exhausted' do
    allow(registry).to receive(:sleep)
    monotonic_times = [0.0, 5.0, 61.0]
    allow(registry).to receive(:monotonic_time) { monotonic_times.shift }

    registry.throttle(:spot_create_order)
    registry.throttle(:spot_create_order)

    expect(registry).to have_received(:sleep).with(55.0).once
  end
end
