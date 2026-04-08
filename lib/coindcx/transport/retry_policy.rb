# frozen_string_literal: true

module CoinDCX
  module Transport
    class RetryPolicy
      def initialize(max_retries:, base_interval:, logger: Logging::NullLogger.new, sleeper: Kernel)
        @max_retries = max_retries
        @base_interval = base_interval
        @logger = logger
        @sleeper = sleeper
      end

      def with_retries(context = {}, retryable: true)
        attempts = 0

        begin
          attempts += 1
          yield(attempts)
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
          raise e unless retryable
          raise e if attempts > @max_retries

          sleep_interval = @base_interval * (2**(attempts - 1))
          Logging::StructuredLogger.log(
            @logger,
            :warn,
            context.merge(
              event: "api_retry",
              retries: attempts,
              error_class: e.class.name,
              message: e.message,
              sleep_interval: sleep_interval
            )
          )
          @sleeper.sleep(sleep_interval)
          retry
        end
      end
    end
  end
end
