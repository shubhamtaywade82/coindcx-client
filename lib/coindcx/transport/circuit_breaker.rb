# frozen_string_literal: true

module CoinDCX
  module Transport
    class CircuitBreaker
      def initialize(threshold:, cooldown:, monotonic_clock: nil)
        @threshold = threshold
        @cooldown = cooldown
        @monotonic_clock = monotonic_clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        @states = {}
        @mutex = Mutex.new
      end

      def guard(key, request_context:)
        return yield if key.nil?

        raise open_error(key, request_context) if open?(key)

        yield.tap { record_success(key) }
      rescue Errors::TransportError, Errors::UpstreamServerError, Errors::RetryableRateLimitError => error
        record_failure(key)
        raise error
      end

      private

      attr_reader :threshold, :cooldown, :monotonic_clock

      def open?(key)
        state = @mutex.synchronize { @states[key] }
        return false if state.nil?
        return false if state.fetch(:failures) < threshold

        monotonic_time < state.fetch(:opened_at) + cooldown
      end

      def record_success(key)
        @mutex.synchronize { @states.delete(key) }
      end

      def record_failure(key)
        @mutex.synchronize do
          state = @states[key] || { failures: 0, opened_at: monotonic_time }
          state[:failures] += 1
          state[:opened_at] = monotonic_time if state[:failures] >= threshold
          @states[key] = state
        end
      end

      def open_error(key, request_context)
        Errors::CircuitOpenError.new(
          "CoinDCX circuit is open for #{key}",
          category: :circuit_open,
          code: "circuit_open",
          request_context: request_context,
          retryable: false
        )
      end

      def monotonic_time
        monotonic_clock.call
      end
    end
  end
end
