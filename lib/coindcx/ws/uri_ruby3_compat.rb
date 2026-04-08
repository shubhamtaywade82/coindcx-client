# frozen_string_literal: true

require "uri"

# socket.io-client-simple 1.2.x builds the Engine.IO query string with URI.encode, which was
# removed in Ruby 3.0 (use URI::DEFAULT_PARSER.escape instead). Load this before socket.io-client-simple.
unless URI.respond_to?(:encode)
  module URI
    def self.encode(str)
      DEFAULT_PARSER.escape(str.to_s)
    end
  end
end
