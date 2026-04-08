# frozen_string_literal: true

require "json"
require "openssl"

module CoinDCX
  module Auth
    class Signer
      def initialize(api_key:, api_secret:)
        @api_key = api_key
        @api_secret = api_secret
      end

      attr_reader :api_key, :api_secret

      def authenticated_request(body = {})
        normalized_body = Utils::Payload.compact_hash(body || {})
        normalized_body[:timestamp] ||= (Time.now.to_f * 1000).floor
        payload = JSON.generate(Utils::Payload.stringify_keys(normalized_body))
        [normalized_body, authentication_headers(payload)]
      end

      def private_channel_join(channel_name: "coindcx")
        channel = Contracts::ChannelName.validate!(channel_name)
        payload = JSON.generate("channel" => channel)

        {
          "channelName" => channel,
          "authSignature" => signature_for(payload),
          "apiKey" => api_key
        }
      end

      def signature_for(payload)
        OpenSSL::HMAC.hexdigest("SHA256", api_secret, payload)
      end

      private

      def authentication_headers(payload)
        {
          "X-AUTH-APIKEY" => api_key,
          "X-AUTH-SIGNATURE" => signature_for(payload)
        }
      end
    end
  end
end
