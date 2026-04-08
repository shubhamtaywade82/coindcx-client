# frozen_string_literal: true

require "simplecov"

SimpleCov.start do
  minimum_coverage 90
  add_filter "/spec/"
end

require "rspec"
require "coindcx"
