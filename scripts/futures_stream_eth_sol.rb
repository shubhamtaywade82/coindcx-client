#!/usr/bin/env ruby
# frozen_string_literal: true

# Streams CoinDCX futures public WebSocket data for ETH and SOL (by default) until interrupted.
# Uses the gem's reconnect on disconnect/heartbeat; adds an outer retry loop if connect bursts fail.
#
# Usage (from repository root):
#   bundle exec ruby scripts/futures_stream_eth_sol.rb
#
# Environment:
#   COINDCX_WS_INSTRUMENTS — comma-separated pair codes (default: B-ETH_USDT,B-SOL_USDT)
#   COINDCX_API_KEY / COINDCX_API_SECRET — optional for public futures only
#
require "logger"
require_relative "../lib/coindcx"

$stdout.sync = true

class FuturesEthSolStream
  DEFAULT_INSTRUMENTS = %w[B-ETH_USDT B-SOL_USDT].freeze
  PRICE_EVENT = "price-change"
  TRADE_EVENT = "new-trade"
  OUTER_RETRY_CAP_SECONDS = 60

  def initialize
    @logger = Logger.new($stderr)
    @logger.level = Logger::INFO
    @ws = nil
  end

  def run
    load_dotenv_if_present
    configure_gem

    instruments = resolve_instruments
    if instruments.empty?
      warn("No instruments (set COINDCX_WS_INSTRUMENTS).")
      exit 2
    end

    client = CoinDCX.client
    @ws = client.ws
    install_shutdown_hooks(client.configuration)

    puts "Subscribing #{instruments.join(', ')} (prices-futures + trades-futures) ..."
    subscribe_all(instruments)

    outer_connect_loop(client.configuration)
  end

  private

  attr_reader :logger, :ws

  def load_dotenv_if_present
    path = File.expand_path("../.env", __dir__)
    return unless File.file?(path)

    File.foreach(path) do |line|
      line = line.strip
      next if line.empty? || line.start_with?("#")

      key, _, value = line.partition("=")
      next if key.empty?

      ENV[key.strip] = value.strip.gsub(/\A["']|["']\z/, "")
    end
    logger.info("Loaded environment from #{path}")
  end

  def configure_gem
    CoinDCX.configure do |config|
      config.api_key = ENV.fetch("COINDCX_API_KEY", nil)
      config.api_secret = ENV.fetch("COINDCX_API_SECRET", nil)
      config.logger = logger
      config.socket_reconnect_attempts = 15
    end
  end

  def resolve_instruments
    raw = ENV.fetch("COINDCX_WS_INSTRUMENTS", "").strip
    if raw.empty?
      DEFAULT_INSTRUMENTS.dup
    else
      raw.split(",").map(&:strip).reject(&:empty?)
    end
  end

  def subscribe_all(instruments)
    pc = CoinDCX::WS::PublicChannels
    instruments.each do |instrument|
      price_channel = pc.futures_price_stats(instrument: instrument)
      trade_channel = pc.futures_new_trade(instrument: instrument)

      ws.subscribe_public(channel_name: price_channel, event_name: PRICE_EVENT) do |payload|
        print_line(instrument, PRICE_EVENT, payload)
      end
      ws.subscribe_public(channel_name: trade_channel, event_name: TRADE_EVENT) do |payload|
        print_line(instrument, TRADE_EVENT, payload)
      end
    end
  end

  def print_line(instrument, event_name, payload)
    ts = Time.now.utc.iso8601(3)
    puts "#{ts} #{instrument} #{event_name} #{payload.inspect}"
  end

  def outer_connect_loop(configuration)
    attempts = 0
    loop do
      ws.connect
      attempts = 0
      puts "Connected to #{configuration.socket_base_url}. Ctrl+C to stop."
      loop { sleep 1 }
    rescue CoinDCX::Errors::SocketConnectionError => e
      attempts += 1
      sleep_seconds = outer_backoff_seconds(attempts, configuration)
      warn("Socket connection error: #{e.message} — retrying in #{sleep_seconds}s (attempt #{attempts})")
      safe_disconnect_ws
      sleep(sleep_seconds)
    end
  end

  def outer_backoff_seconds(attempts, configuration)
    base = configuration.socket_reconnect_interval
    scaled = base * (2**(attempts - 1))
    [scaled, OUTER_RETRY_CAP_SECONDS].min
  end

  def safe_disconnect_ws
    ws.disconnect
  rescue CoinDCX::Errors::SocketError
    # ignore
  end

  def install_shutdown_hooks(configuration)
    socket_client = ws
    url = configuration.socket_base_url
    %w[INT TERM].each do |sig|
      Signal.trap(sig) do
        warn("\nInterrupted; disconnecting from #{url}")
        # Mutexes (e.g. in ConnectionManager) cannot run inside trap context; disconnect off-thread.
        Thread.new do
          socket_client&.disconnect
        rescue CoinDCX::Errors::SocketError
          # ignore
        end.join
        exit 130
      end
    end
  end
end

begin
  FuturesEthSolStream.new.run
rescue CoinDCX::Errors::SocketAuthenticationError => e
  warn("Authentication failed: #{e.message}")
  exit 4
rescue CoinDCX::Errors::ValidationError => e
  warn("Invalid instrument or channel: #{e.message}")
  exit 2
end
