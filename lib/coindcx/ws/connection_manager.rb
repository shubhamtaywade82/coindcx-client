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
         @subscriptions = []
         @handlers = Hash.new { |hash, key| hash[key] = [] }
         @registered_event_names = Set.new
         @mutex = Mutex.new
         @last_activity_at = monotonic_time
       end

      def connect
        return self if state.connected? || state.connecting? || state.reconnecting?

         state.transition_to(:connecting)
         connect_with_retries
         start_heartbeat
         self
       end

      def disconnect
        state.transition_to(:stopping)
        stop_heartbeat
        backend.disconnect
        state.transition_to(:disconnected)
        self
      rescue Errors::SocketError
        state.transition_to(:disconnected)
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

       def subscribe(type:, channel_name:, event_name:, payload:)
         mutex.synchronize do
           subscription = {
             type: type,
             channel_name: channel_name,
             event_name: event_name,
             payload: payload
           }

           subscriptions << subscription unless subscriptions.include?(subscription)
           register_event_bridge(event_name) if state.connected?
         end

         emit_join(payload) if state.connected?
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
         rescue Errors::SocketConnectionError => e
           raise e if attempts > max_retries

           state.transition_to(:reconnecting)
           sleep_interval = reconnect_interval(attempts)
           log(:warn, event: "ws_reconnect_retry", retries: attempts, latency: nil, endpoint: configuration.socket_base_url,
                      error_class: e.class.name, message: e.message, sleep_interval: sleep_interval)
           sleeper.sleep(sleep_interval)
           retry
         end
       end

       def establish_connection
         backend.connect(configuration.socket_base_url)
         touch_activity!
         register_runtime_handlers
         resubscribe_all
         state.transition_to(:connected)
         log(:info, event: "ws_connected", retries: 0, latency: nil, endpoint: configuration.socket_base_url)
       end

       def register_runtime_handlers
         @registered_event_names = Set.new
         backend.on(:connect) { handle_connect }
         backend.on(:disconnect) { handle_disconnect }
         subscribed_event_names.each { |event_name| register_event_bridge(event_name) }
       end

       def handle_connect
         touch_activity!
         state.transition_to(:connected)
       end

       def handle_disconnect
         return if state.stopping? || state.reconnecting?

         state.transition_to(:disconnected)
         log(:warn, event: "ws_disconnected", retries: 0, latency: nil, endpoint: configuration.socket_base_url)
         reconnect
       end

       def reconnect
         return unless begin_reconnect

         state.transition_to(:reconnecting)
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
         subscriptions.each do |subscription|
           emit_join(subscription.fetch(:payload))
         end
       end

       def emit_join(payload)
         backend.emit("join", payload)
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
         rescue StandardError => e
           log(:error, event: "ws_handler_error", retries: 0, latency: nil, endpoint: event_name,
                       error_class: e.class.name, message: e.message)
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
         log(:error, event: "ws_heartbeat_failed", retries: 0, latency: nil, endpoint: configuration.socket_base_url,
                     error_class: e.class.name, message: e.message)
       end

      def check_liveness!
        return unless heartbeat_required?
        return unless stale_connection?

        log(:warn, event: "ws_heartbeat_stale", retries: 0, latency: liveness_age, endpoint: configuration.socket_base_url)
        reconnect
      end

       def heartbeat_required?
        state.connected? && subscriptions.any?
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

       def subscribed_event_names
        (subscriptions.map { |subscription| subscription.fetch(:event_name) } + handlers.keys).uniq
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
