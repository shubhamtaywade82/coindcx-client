# frozen_string_literal: true

module CoinDCX
  module Utils
    module Payload
      module_function

      def compact_hash(object)
        case object
        when Hash
          object.each_with_object({}) do |(key, value), result|
            compact_value = compact_hash(value)
            next if compact_value.nil?

            result[key] = compact_value
          end
        when Array
          object.filter_map { |value| compact_hash(value) }
        else
          object
        end
      end

      def stringify_keys(object)
        case object
        when Hash
          object.each_with_object({}) do |(key, value), result|
            result[key.to_s] = stringify_keys(value)
          end
        when Array
          object.map { |value| stringify_keys(value) }
        else
          object
        end
      end

      def symbolize_keys(object)
        case object
        when Hash
          object.each_with_object({}) do |(key, value), result|
            result[key.to_sym] = symbolize_keys(value)
          end
        when Array
          object.map { |value| symbolize_keys(value) }
        else
          object
        end
      end
    end
  end
end
