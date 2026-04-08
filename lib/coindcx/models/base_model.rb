# frozen_string_literal: true

module CoinDCX
  module Models
    class BaseModel
      def initialize(attributes = {})
        @attributes = Utils::Payload.symbolize_keys(attributes || {})
      end

      attr_reader :attributes

      def [](key)
        attributes[key.to_sym]
      end

      def to_h
        attributes.dup
      end

      def respond_to_missing?(method_name, include_private = false)
        attributes.key?(method_name.to_sym) || super
      end

      def method_missing(method_name, *arguments)
        return attributes.fetch(method_name.to_sym) if arguments.empty? && attributes.key?(method_name.to_sym)

        super
      end
    end
  end
end
