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

      def with_retries(context = {}, policy:)
        attempts = 0

        begin
          attempts += 1
          yield(attempts)
        rescue Errors::ApiError => e
          raise e unless retryable_api_error?(attempts, e, policy)

          retry_request(context, attempts, e, policy)
          retry
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
          raise transport_error_for(e, context) unless retryable_transport_error?(attempts, policy)

          retry_request(context, attempts, e, policy)
          retry
        end
      end

      private

      def retryable_api_error?(attempts, error, policy)
        error.retryable && attempts <= retry_limit(policy)
      end

      def retryable_transport_error?(attempts, policy)
        policy.retryable_transport_error? && attempts <= retry_limit(policy)
      end

      def retry_request(context, attempts, error, policy)
        sleep_interval = retry_sleep_interval(attempts, error, policy)
        Logging::StructuredLogger.log(
          @logger,
          :warn,
          context.merge(
            event: "api_retry",
            retries: attempts,
            error_class: error.class.name,
            message: error.message,
            sleep_interval: sleep_interval
          )
        )
        @sleeper.sleep(sleep_interval)
      end

      def retry_sleep_interval(attempts, error, policy)
        return error.retry_after.to_f if error.respond_to?(:retry_after) && error.retry_after.to_f.positive?

        @base_interval * (2**(attempts - 1))
      end

      def retry_limit(policy)
        [policy.retry_budget, @max_retries].min
      end

      def transport_error_for(error, context)
        Errors::TransportError.new(
          "CoinDCX transport failed for #{context.fetch(:endpoint)}",
          category: :transport,
          code: error.class.name,
          request_context: context,
          retryable: false
        ).tap { |wrapped_error| wrapped_error.set_backtrace(error.backtrace) }
      end
    end
  end
end
