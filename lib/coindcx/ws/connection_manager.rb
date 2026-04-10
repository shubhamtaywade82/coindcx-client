# frozen_string_literal: true

require "json"

module CoinDCX
  module WS
    class ConnectionManager
      MAX_RETRIES = 5
      MAX_BACKOFF_INTERVAL = 30.0

      def initialize(configuration:, backend:, logger:, sleeper: Kernel, thread_factory: nil, monotonic_clock: nil, randomizer: nil)
        @configuration = configuration
        @backend = backend
        @logger = logger
        @sleeper = sleeper
        @thread_factory = thread_factory || ->(&block) { Thread.new(&block) }
        @monotonic_clock = monotonic_clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        @randomizer = randomizer || -> { rand }
        @state = ConnectionState.new
        @subscriptions = SubscriptionRegistry.new
        @handlers = Hash.new { |hash, key| hash[key] = [] }
        @registered_event_names = Set.new
        @mutex = Mutex.new
        @last_activity_at = monotonic_time
        @engine_io_open = false
      end

      def connect
        return self if state.connected? || state.connecting? || state.reconnecting?

        transition_to(:connecting)
        connect_with_retries
        start_heartbeat
        self
      end

      def disconnect
        return self if state.current == :disconnected || state.stopping?

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
        emit_join(subscription_for(type: type, channel_name: channel_name, event_name: event_name)) if state.connected? && @engine_io_open
        transition_to(:subscribed) if state.connected? && subscriptions.any?
        self
      end

      def alive?
        return false unless state.connected?
        return true unless subscriptions.any?

        !stale_connection?
      end

      private

      attr_reader :configuration, :backend, :logger, :sleeper, :thread_factory,
                  :monotonic_clock, :randomizer, :state, :subscriptions, :handlers, :mutex,
                  :registered_event_names

      def connect_with_retries
        attempts = 0

        begin
          attempts += 1
          establish_connection
        rescue Errors::SocketAuthenticationError => e
          transition_to(:failed)
          log(
            :error,
            event: "ws_failed",
            endpoint: configuration.socket_base_url,
            retries: attempts - 1,
            latency: nil,
            error_class: e.class.name,
            message: e.message,
            subscription_count: subscriptions.count
          )
          raise e
        rescue Errors::SocketConnectionError => e
          handle_reconnect_failure(attempts, e)
          retry
        end
      end

      def establish_connection
        @engine_io_open = false
        backend.connect(configuration.socket_base_url)
        register_runtime_handlers
        backend.start_transport!
        touch_activity!
        transition_to(:authenticated)
      end

      def register_runtime_handlers
        @registered_event_names = Set.new
        # socket.io-client-simple uses event_emitter's instance_exec(socket, *args) for listeners,
        # so blocks must not rely on implicit self (handle_* would resolve on the socket client).
        manager = self
        backend.on(:connect) { |*_args| manager.send(:handle_connect) }
        backend.on(:disconnect) { |*_args| manager.send(:handle_disconnect) }
        subscriptions.event_names.each { |event_name| register_event_bridge(event_name) }
      end

      def handle_connect
        touch_activity!
        @engine_io_open = true
        resubscribe_all
        transition_to(subscriptions.any? ? :subscribed : :authenticated)
      end

      def handle_disconnect
        return if state.stopping? || state.reconnecting?

        @engine_io_open = false
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
        return unless begin_reconnect?

        transition_to(:reconnecting)
        stop_heartbeat
        backend.disconnect
        connect_with_retries
        start_heartbeat
      ensure
        finish_reconnect
      end

      def begin_reconnect?
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
      rescue Errors::AuthError => e
        raise Errors::SocketAuthenticationError,
              "private websocket authentication failed for #{subscription.channel_name}: #{e.message}"
      end

      def register_event_bridge(event_name)
        return if registered_event_names.include?(event_name)

        manager = self
        # Socket.IO may emit multiple data frames after the event name, e.g. [channelName, payloadHash].
        # Forwarding only the first argument often yields a bare String and drops the price object.
        backend.on(event_name) do |*args|
          manager.send(:touch_activity!)
          coalesced = manager.send(:coalesce_socket_event_payload, args)
          normalized = manager.send(:normalize_coin_dcx_event_payload, coalesced)
          manager.send(:dispatch, event_name, normalized)
        end

        registered_event_names << event_name
      end

      def coalesce_socket_event_payload(args)
        parts = Array(args).flatten(1).compact
        return nil if parts.empty?
        return parts.first if parts.size == 1

        hashes = parts.grep(Hash)
        return hashes.reduce { |acc, h| acc.merge(h) } if hashes.size > 1
        return hashes.first if hashes.size == 1

        parts.last
      end

      # CoinDCX often sends { "event" => "...", "data" => "<JSON string of fields>" }. Merge parsed
      # fields into the top-level hash so consumers see p / s / etc. without a second parse.
      def normalize_coin_dcx_event_payload(payload)
        return payload unless payload.is_a?(Hash)

        %w[data payload].each do |key|
          raw = payload[key] || payload[key.to_sym]
          next unless raw.is_a?(String) && !raw.strip.empty?

          parsed = JSON.parse(raw)
          next unless parsed.is_a?(Hash)

          merged = payload.merge(parsed)
          merged.delete(key)
          merged.delete(key.to_sym)
          return merged
        end

        payload
      rescue JSON::ParserError
        payload
      end

      def dispatch(event_name, payload)
        handlers.fetch(event_name, []).each do |handler|
          handler.call(payload)
        rescue StandardError => e
          log(
            :error,
            event: "ws_handler_error",
            endpoint: event_name,
            retries: 0,
            latency: nil,
            error_class: e.class.name,
            message: e.message
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
      rescue StandardError => e
        log(
          :error,
          event: "ws_heartbeat_failed",
          endpoint: configuration.socket_base_url,
          retries: 0,
          latency: nil,
          error_class: e.class.name,
          message: e.message
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

        subscriptions.any?
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
        raw = configuration.socket_reconnect_interval * (2**(attempts - 1))
        base = [raw, MAX_BACKOFF_INTERVAL].min
        base + (base * 0.25 * randomizer.call)
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

      def log(level, payload)
        Logging::StructuredLogger.log(logger, level, payload)
      end
    end
  end
end
