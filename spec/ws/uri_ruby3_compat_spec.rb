# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/coindcx/ws/uri_ruby3_compat"

RSpec.describe "CoinDCX::WS URI.encode shim (Ruby 3 + socket.io-client-simple)" do
  it "restores URI.encode using DEFAULT_PARSER so Engine.IO query params build" do
    # rubocop:disable Lint/UriEscapeUnescape -- intentional: shim matches legacy URI.encode for socket.io-client-simple
    expect(URI.encode("EIO=4")).to eq(URI::DEFAULT_PARSER.escape("EIO=4"))
    # rubocop:enable Lint/UriEscapeUnescape
  end
end
