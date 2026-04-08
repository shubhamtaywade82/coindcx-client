 # frozen_string_literal: true

 module CoinDCX
   module Contracts
     module OrderRequest
       VALID_SIDES = %w[buy sell].freeze

       module_function

       def validate_spot_create!(attributes)
         validate_side!(attributes)
         validate_positive_quantity!(attributes, :total_quantity)
         attributes
       end

       def validate_spot_create_many!(orders)
         Array(orders).each { |order| validate_spot_create!(order) }
         orders
       end

       def validate_futures_create!(attributes)
         validate_side!(attributes)
         validate_positive_quantity!(attributes, :quantity, :size)
         attributes
       end

       def validate_margin_create!(attributes)
         validate_side!(attributes)
         validate_positive_quantity!(attributes, :quantity, :total_quantity)
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
     end
   end
 end
