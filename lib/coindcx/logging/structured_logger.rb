 # frozen_string_literal: true

 module CoinDCX
   module Logging
     module StructuredLogger
       module_function

       def log(logger, level, payload)
         return unless logger.respond_to?(level)

         logger.public_send(level, payload)
       rescue ArgumentError, TypeError
         logger.public_send(level, payload.inspect)
       end
     end
   end
 end
