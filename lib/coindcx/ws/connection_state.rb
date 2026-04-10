# frozen_string_literal: true

module CoinDCX
  module WS
    class ConnectionState
      VALID_STATES = %i[disconnected connecting authenticated subscribed reconnecting failed stopping].freeze

      # Allowed forward-transitions for each state.  Any transition not listed here
      # is a programming error and will raise +SocketStateError+.
      VALID_TRANSITIONS = {
        disconnected: %i[connecting reconnecting],
        connecting: %i[authenticated failed reconnecting stopping],
        authenticated: %i[subscribed reconnecting stopping disconnected],
        subscribed: %i[reconnecting stopping authenticated disconnected],
        reconnecting: %i[authenticated subscribed failed stopping disconnected],
        failed: %i[connecting stopping disconnected],
        stopping: %i[disconnected]
      }.freeze

      def initialize
        @value = :disconnected
        @mutex = Mutex.new
      end

      def transition_to(next_state)
        raise Errors::SocketError, "invalid connection state: #{next_state.inspect}" unless VALID_STATES.include?(next_state)

        @mutex.synchronize do
          return if @value == next_state

          allowed = VALID_TRANSITIONS.fetch(@value, [])
          unless allowed.include?(next_state)
            raise Errors::SocketStateError,
                  "invalid state transition: #{@value} → #{next_state} " \
                  "(allowed from #{@value}: #{allowed.inspect})"
          end

          @value = next_state
        end
      end

      def current
        @mutex.synchronize { @value }
      end

      def connected?
        authenticated? || subscribed?
      end

      def connecting?
        current == :connecting
      end

      def authenticated?
        current == :authenticated
      end

      def subscribed?
        current == :subscribed
      end

      def reconnecting?
        current == :reconnecting
      end

      def failed?
        current == :failed
      end

      def stopping?
        current == :stopping
      end
    end
  end
end
