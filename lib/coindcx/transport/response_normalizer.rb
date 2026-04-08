 # frozen_string_literal: true

 module CoinDCX
   module Transport
     module ResponseNormalizer
       module_function

       def success(data)
         {
           success: true,
           data: data,
           error: nil
         }
       end

       def failure(status:, body:, fallback_message:)
         normalized_body = normalize_body(body)

         {
           success: false,
           data: {},
           error: {
             code: normalized_body[:code] || status,
             message: normalized_body[:message] || normalized_body[:error] || fallback_message
           }
         }
       end

       def normalize_body(body)
         return Utils::Payload.symbolize_keys(body) if body.is_a?(Hash)
         return { message: body } if body.is_a?(String)

         {}
       end
     end
   end
 end
