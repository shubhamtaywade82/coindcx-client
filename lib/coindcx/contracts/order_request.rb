# frozen_string_literal: true

module CoinDCX
  module Contracts
    module OrderRequest
      VALID_SIDES = %w[buy sell].freeze
      VALID_SPOT_ORDER_TYPES = %w[market_order limit_order stop_limit take_profit].freeze
      VALID_MARGIN_ORDER_TYPES = %w[market_order limit_order stop_limit take_profit].freeze

      module_function

      def validate_spot_create!(attributes)
        validate_side!(attributes)
        validate_order_type!(attributes, VALID_SPOT_ORDER_TYPES)
        validate_market!(attributes)
        validate_positive_quantity!(attributes, :total_quantity)
        validate_positive_number!(attributes, :price_per_unit) if present?(attributes, :price_per_unit)
        attributes
      end

      def validate_spot_create_many!(orders)
        Array(orders).each { |order| validate_spot_create!(order) }
        orders
      end

      def validate_futures_create!(attributes)
        validate_side!(attributes)
        validate_pair!(attributes, :pair) if present?(attributes, :pair)
        validate_pair!(attributes, :instrument) if present?(attributes, :instrument)
        validate_positive_quantity!(attributes, :quantity, :size, :total_quantity)
        attributes
      end

      def validate_margin_create!(attributes)
        validate_side!(attributes)
        validate_order_type!(attributes, VALID_MARGIN_ORDER_TYPES)
        validate_market!(attributes)
        validate_positive_quantity!(attributes, :quantity, :total_quantity)
        validate_positive_number!(attributes, :price_per_unit) if present?(attributes, :price_per_unit)
        attributes
      end

      def validate_side!(attributes)
        side = fetch_required(attributes, :side)
        return side if VALID_SIDES.include?(side.to_s)

        raise Errors::ValidationError, "side must be one of: #{VALID_SIDES.join(', ')}"
      end

      def validate_positive_quantity!(attributes, *keys)
        quantity = fetch_quantity(attributes, keys)
        return quantity if quantity.to_f.positive?

        raise Errors::ValidationError, "#{keys.join(' or ')} must be greater than 0"
      end

      def validate_positive_number!(attributes, key)
        value = fetch_required(attributes, key)
        return value if value.to_f.positive?

        raise Errors::ValidationError, "#{key} must be greater than 0"
      end

      def validate_order_type!(attributes, valid_order_types)
        order_type = fetch_required(attributes, :order_type)
        return order_type if valid_order_types.include?(order_type.to_s)

        raise Errors::ValidationError, "order_type must be one of: #{valid_order_types.join(', ')}"
      end

      def validate_market!(attributes)
        Identifiers.validate_market!(fetch_required(attributes, :market))
      end

      def validate_pair!(attributes, key)
        Identifiers.validate_pair!(fetch_required(attributes, key))
      end

      def fetch_quantity(attributes, keys)
        keys.each do |key|
          value = fetch_optional(attributes, key)
          return value unless value.nil?
        end

        raise Errors::ValidationError, "#{keys.join(' or ')} is required"
      end

      def fetch_required(attributes, key)
        value = fetch_optional(attributes, key)
        return value unless value.nil?

        raise Errors::ValidationError, "#{key} is required"
      end

      def fetch_optional(attributes, key)
        return attributes[key] if attributes.key?(key)
        return attributes[key.to_s] if attributes.key?(key.to_s)

        nil
      end

      def present?(attributes, key)
        !fetch_optional(attributes, key).nil?
      end
    end
  end
end
