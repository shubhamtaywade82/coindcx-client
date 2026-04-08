 # frozen_string_literal: true

 module CoinDCX
   module WS
     class ConnectionState
       VALID_STATES = %i[disconnected connecting connected reconnecting stopping].freeze

       def initialize
         @value = :disconnected
         @mutex = Mutex.new
       end

       def transition_to(next_state)
         raise Errors::SocketError, "invalid connection state: #{next_state.inspect}" unless VALID_STATES.include?(next_state)

         @mutex.synchronize { @value = next_state }
       end

       def current
         @mutex.synchronize { @value }
       end

       def connected?
         current == :connected
       end

       def connecting?
         current == :connecting
       end

       def reconnecting?
         current == :reconnecting
       end

       def stopping?
         current == :stopping
       end
     end
   end
 end
