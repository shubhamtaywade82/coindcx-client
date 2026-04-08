# frozen_string_literal: true

module CoinDCX
  module Transport
    class RateLimitRegistry
      def initialize(definitions = {})
        @definitions = definitions.transform_keys(&:to_sym)
        @timestamps = Hash.new { |hash, key| hash[key] = [] }
        @mutex = Mutex.new
      end

      def acquire(bucket_name)
        return if bucket_name.nil?

        definition = @definitions[bucket_name.to_sym]
        return if definition.nil?

        loop do
          wait_time = @mutex.synchronize do
            reserve_slot(bucket_name, definition)
          end

          return if wait_time.nil? || wait_time <= 0

          sleep(wait_time)
        end
      end

      private

      def reserve_slot(bucket_name, definition)
        bucket_key = bucket_name.to_sym
        now = monotonic_time
        cutoff = now - definition.fetch(:period).to_f
        bucket = @timestamps[bucket_key]
        bucket.reject! { |timestamp| timestamp <= cutoff }

        if bucket.length < definition.fetch(:limit)
          bucket << now
          return nil
        end

        definition.fetch(:period).to_f - (now - bucket.first)
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
