# frozen_string_literal: true

module CoinDCX
  module Transport
    class RetryPolicy
      def initialize(max_retries:, base_interval:, logger: Logging::NullLogger.new)
        @max_retries = max_retries
        @base_interval = base_interval
        @logger = logger
      end

      def with_retries(context = {})
        attempts = 0

        begin
          attempts += 1
          yield(attempts)
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
          raise error if attempts > @max_retries

          sleep_interval = @base_interval * (2**(attempts - 1))
          @logger.warn("Retrying CoinDCX request after #{error.class}: #{context.inspect}, attempt=#{attempts}, sleep=#{sleep_interval}")
          sleep(sleep_interval)
          retry
        end
      end
    end
  end
end
