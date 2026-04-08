# frozen_string_literal: true

module CoinDCX
  module REST
    class BaseResource
      def initialize(http_client:)
        @http_client = http_client
      end

      private

      attr_reader :http_client

      def get(path, params: {}, body: {}, auth: false, base: :api, bucket: nil)
        http_client.get(path, params: params, body: body, auth: auth, base: base, bucket: bucket)
      end

      def post(path, body: {}, auth: false, base: :api, bucket: nil)
        http_client.post(path, body: body, auth: auth, base: base, bucket: bucket)
      end

      def delete(path, body: {}, auth: false, base: :api, bucket: nil)
        http_client.delete(path, body: body, auth: auth, base: base, bucket: bucket)
      end

      def build_model(model_class, attributes)
        model_class.new(attributes)
      end

      def build_models(model_class, collection)
        Array(collection).map { |attributes| model_class.new(attributes) }
      end
    end
  end
end
