# frozen_string_literal: true

module CoinDCX
  module WS
    class SubscriptionRegistry
      SubscriptionIntent = Struct.new(
        :type,
        :channel_name,
        :event_name,
        :payload_builder,
        :delivery_mode
      ) do
        def payload
          payload_builder.call
        end

        def private_channel?
          type == :private
        end
      end

      def initialize
        @subscriptions = []
        @mutex = Mutex.new
      end

      def add(type:, channel_name:, event_name:, payload_builder:, delivery_mode:)
        @mutex.synchronize do
          subscription = SubscriptionIntent.new(
            type: type,
            channel_name: channel_name,
            event_name: event_name,
            payload_builder: payload_builder,
            delivery_mode: delivery_mode
          )

          @subscriptions << subscription unless include?(subscription)
        end
      end

      def each(&block)
        snapshot.each(&block)
      end

      def any?
        snapshot.any?
      end

      def count
        snapshot.count
      end

      def event_names
        snapshot.map(&:event_name).uniq
      end

      def private_subscriptions?
        snapshot.any?(&:private_channel?)
      end

      def public_subscriptions?
        snapshot.any? { |subscription| !subscription.private_channel? }
      end

      private

      def include?(candidate)
        @subscriptions.any? do |subscription|
          subscription.type == candidate.type &&
            subscription.channel_name == candidate.channel_name &&
            subscription.event_name == candidate.event_name
        end
      end

      def snapshot
        @mutex.synchronize { @subscriptions.dup }
      end
    end
  end
end
