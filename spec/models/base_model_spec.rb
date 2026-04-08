# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CoinDCX::Models::BaseModel do
  subject(:model) { described_class.new('status' => 'open', 'nested' => { 'count' => 2 }) }

  it 'provides hash-like and method-style access to attributes' do
    expect(model[:status]).to eq('open')
    expect(model.status).to eq('open')
    expect(model.to_h).to eq(status: 'open', nested: { count: 2 })
  end

  it 'reports dynamic methods through respond_to?' do
    expect(model).to respond_to(:status)
    expect(model).not_to respond_to(:missing_attribute)
  end
end
