# frozen_string_literal: true

module CoinDCX
  module Logging
    class NullLogger
      def debug(*) = nil
      def info(*) = nil
      def warn(*) = nil
      def error(*) = nil
    end
  end
end
