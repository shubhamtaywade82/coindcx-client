# frozen_string_literal: true

require "set"

module CoinDCX
  module WS
    class ConnectionManager
      MAX_RETRIES = 5

      def initialize(configuration:, backend:, logger:, sleeper: Kernel, thread_factory: nil, monotonic_clock: nil)
        @configuration = configuration
        @backend = backend
        @logger = logger
        @sleeper = sleeper
        @thread_factory = thread_factory || ->(&block) { Thread.new(&block) }
        @monotonic_clock = monotonic_clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        @state = ConnectionState.new
        @subscriptions = SubscriptionRegistry.new
        @handlers = Hash.new { |hash, key| hash[key] = [] }
        @registered_event_names = Set.new
        @mutex = Mutex.new
        @last_activity_at = monotonic_time
      end

      def connect
        return self if state.connected? || state.connecting? || state.reconnecting?

        transition_to(:connecting)
        connect_with_retries
        start_heartbeat
        self
      end

      def disconnect
        transition_to(:stopping)
        stop_heartbeat
        backend.disconnect
        transition_to(:disconnected)
        self
      rescue Errors::SocketError
        transition_to(:disconnected)
        self
      end

      def on(event_name, &block)
        return self unless block_given?

        mutex.synchronize do
          handlers[event_name] << block
          register_event_bridge(event_name) if state.connected?
        end

        self
      end

      def subscribe(type:, channel_name:, event_name:, payload_builder:, delivery_mode:)
        subscriptions.add(
          type: type,
          channel_name: channel_name,
          event_name: event_name,
          payload_builder: payload_builder,
          delivery_mode: delivery_mode
        )
        register_event_bridge(event_name) if state.connected?
        emit_join(subscription_for(type: type, channel_name: channel_name, event_name: event_name)) if state.connected?
        transition_to(:subscribed) if state.connected?
        self
      end

      def alive?
        return false unless state.connected?
        return true unless subscriptions.any?

        !stale_connection?
      end

      private

      attr_reader :configuration, :backend, :logger, :sleeper, :thread_factory,
                  :monotonic_clock, :state, :subscriptions, :handlers, :mutex

      def connect_with_retries
        attempts = 0

        begin
          attempts += 1
          establish_connection
        rescue Errors::SocketAuthenticationError => error
          transition_to(:failed)
          log(
            :error,
            event: "ws_failed",
            endpoint: configuration.socket_base_url,
            retries: attempts - 1,
            latency: nil,
            error_class: error.class.name,
            message: error.message,
            subscription_count: subscriptions.count
          )
          raise error
        rescue Errors::SocketConnectionError => error
          handle_reconnect_failure(attempts, error)
          retry
        end
      end

      def establish_connection
        backend.connect(configuration.socket_base_url)
        touch_activity!
        register_runtime_handlers
        transition_to(:authenticated)
        resubscribe_all
        transition_to(:subscribed) if subscriptions.any?
      end

      def register_runtime_handlers
        @registered_event_names = Set.new
        backend.on(:connect) { handle_connect }
        backend.on(:disconnect) { handle_disconnect }
        subscriptions.event_names.each { |event_name| register_event_bridge(event_name) }
      end

      def handle_connect
        touch_activity!
        transition_to(subscriptions.any? ? :subscribed : :authenticated)
      end

      def handle_disconnect
        return if state.stopping? || state.reconnecting?

        transition_to(:disconnected)
        log(
          :warn,
          event: "ws_disconnected",
          endpoint: configuration.socket_base_url,
          retries: 0,
          latency: nil,
          subscription_count: subscriptions.count
        )
        reconnect
      end

      def reconnect
        return unless begin_reconnect

        transition_to(:reconnecting)
        stop_heartbeat
        backend.disconnect
        connect_with_retries
        start_heartbeat
      ensure
        finish_reconnect
      end

      def begin_reconnect
        mutex.synchronize do
          return false if @reconnecting

          @reconnecting = true
        end

        true
      end

      def finish_reconnect
        mutex.synchronize { @reconnecting = false }
      end

      def resubscribe_all
        subscriptions.each { |subscription| emit_join(subscription) }
      end

      def emit_join(subscription)
        payload = subscription.payload
        backend.emit("join", payload)
      rescue Errors::AuthError => error
        raise Errors::SocketAuthenticationError,
              "private websocket authentication failed for #{subscription.channel_name}: #{error.message}"
      end

      def register_event_bridge(event_name)
        return if registered_event_names.include?(event_name)

        backend.on(event_name) do |payload|
          touch_activity!
          dispatch(event_name, payload)
        end

        registered_event_names << event_name
      end

      def dispatch(event_name, payload)
        handlers.fetch(event_name, []).each do |handler|
          handler.call(payload)
        rescue StandardError => error
          log(
            :error,
            event: "ws_handler_error",
            endpoint: event_name,
            retries: 0,
            latency: nil,
            error_class: error.class.name,
            message: error.message
          )
        end
      end

      def start_heartbeat
        stop_heartbeat
        token = Object.new
        @heartbeat_token = token
        @heartbeat_thread = thread_factory.call { heartbeat_loop(token) }
      end

      def stop_heartbeat
        @heartbeat_token = nil
        @heartbeat_thread = nil
      end

      def heartbeat_loop(token)
        loop do
          sleeper.sleep(configuration.socket_heartbeat_interval)
          break unless @heartbeat_token.equal?(token)

          check_liveness!
        end
      rescue StandardError => error
        log(
          :error,
          event: "ws_heartbeat_failed",
          endpoint: configuration.socket_base_url,
          retries: 0,
          latency: nil,
          error_class: error.class.name,
          message: error.message
        )
      end

      def check_liveness!
        return unless heartbeat_required?
        return unless stale_connection?

        timeout_error = Errors::SocketHeartbeatTimeoutError.new(
          "CoinDCX websocket heartbeat timed out",
          category: :socket_timeout,
          code: "socket_heartbeat_timeout",
          retryable: true
        )
        log(
          :warn,
          event: "ws_heartbeat_stale",
          endpoint: configuration.socket_base_url,
          retries: 0,
          latency: liveness_age,
          subscription_count: subscriptions.count,
          error_class: timeout_error.class.name,
          message: timeout_error.message
        )
        reconnect
      end

      def heartbeat_required?
        return false unless state.connected?
        return false unless subscriptions.any?

        subscriptions.public_subscriptions?
      end

      def stale_connection?
        liveness_age > configuration.socket_liveness_timeout
      end

      def liveness_age
        monotonic_time - mutex.synchronize { @last_activity_at }
      end

      def touch_activity!
        mutex.synchronize { @last_activity_at = monotonic_time }
      end

      def monotonic_time
        monotonic_clock.call
      end

      def reconnect_interval(attempts)
        configuration.socket_reconnect_interval * (2**(attempts - 1))
      end

      def max_retries
        configuration.socket_reconnect_attempts || MAX_RETRIES
      end

      def handle_reconnect_failure(attempts, error)
        if attempts > max_retries
          transition_to(:failed)
          log(
            :error,
            event: "ws_failed",
            endpoint: configuration.socket_base_url,
            retries: attempts - 1,
            latency: nil,
            error_class: error.class.name,
            message: error.message,
            subscription_count: subscriptions.count
          )
          raise error
        end

        transition_to(:reconnecting)
        sleep_interval = reconnect_interval(attempts)
        log(
          :warn,
          event: "ws_reconnect_retry",
          endpoint: configuration.socket_base_url,
          retries: attempts,
          latency: nil,
          error_class: error.class.name,
          message: error.message,
          sleep_interval: sleep_interval,
          subscription_count: subscriptions.count
        )
        sleeper.sleep(sleep_interval)
      end

      def transition_to(next_state)
        previous_state = state.current
        return if previous_state == next_state

        state.transition_to(next_state)
        log(
          :info,
          event: "ws_state_transition",
          endpoint: configuration.socket_base_url,
          retries: 0,
          latency: nil,
          from: previous_state,
          to: next_state,
          subscription_count: subscriptions.count
        )
      end

      def subscription_for(type:, channel_name:, event_name:)
        subscriptions.each do |subscription|
          return subscription if subscription.type == type &&
                                subscription.channel_name == channel_name &&
                                subscription.event_name == event_name
        end

        raise Errors::SocketStateError, "subscription intent not registered for #{event_name}"
      end

      def registered_event_names
        @registered_event_names
      end

      def log(level, payload)
        Logging::StructuredLogger.log(logger, level, payload)
      end
    end
  end
end
