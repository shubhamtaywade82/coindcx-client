#!/usr/bin/env ruby
# frozen_string_literal: true

# Subscribes to CoinDCX **Futures** WebSocket channels from the public API docs (public + optional private).
# Same Socket.IO endpoint as spot (`wss://stream.coindcx.com`); channel names use `-futures` / `@futures` suffixes.
#
# Usage (repo root):
#   bundle exec ruby scripts/futures_sockets_smoke.rb
#
# Environment:
#   COINDCX_WS_INSTRUMENT       — instrument id e.g. B-BTC_USDT (default: B-BTC_USDT)
#   COINDCX_CANDLE_INTERVAL     — e.g. 1m, 1h (default: 1m)
#   COINDCX_ORDERBOOK_DEPTH     — 10, 20, or 50 (default: 20)
#   COINDCX_API_KEY / COINDCX_API_SECRET — enables private `coindcx` df-* + balance streams
#   COINDCX_FUTURES_VERBOSE     — 1 / true / yes for full currentPrices@futures payloads
#   COINDCX_FUTURES_THROTTLE    — print every Nth currentPrices@futures#update (default: 6)
#
# WebSocket blocks receive a single coalesced payload (Socket.IO multi-arg frames are merged server-side by the client).
#
require "logger"
require "time"
require_relative "../lib/coindcx"

$stdout.sync = true

class FuturesSocketsSmoke
  def initialize
    @logger = Logger.new($stderr)
    @logger.level = Logger::INFO
    @ws = nil
    @tick = Hash.new(0)
  end

  def run
    load_dotenv_if_present
    configure_gem
    apply_environment!

    client = CoinDCX.client
    @ws = client.ws
    install_shutdown_hooks(client.configuration)

    print_banner
    subscribe_documented_public_streams!
    subscribe_private_streams_if_configured!

    outer_connect_loop(client.configuration)
  end

  private

  attr_reader :logger, :ws, :throttle, :verbose, :tick

  def apply_environment!
    @instrument = ENV.fetch("COINDCX_WS_INSTRUMENT", "B-BTC_USDT").strip
    @candle_interval = ENV.fetch("COINDCX_CANDLE_INTERVAL", "1m").strip
    @orderbook_depth = Integer(ENV.fetch("COINDCX_ORDERBOOK_DEPTH", "20"))
    @throttle = Integer(ENV.fetch("COINDCX_FUTURES_THROTTLE", "6"))
    @verbose = %w[1 true yes].include?(ENV.fetch("COINDCX_FUTURES_VERBOSE", "").downcase)
  end

  def print_banner
    pc = CoinDCX::WS::PublicChannels
    puts <<~BANNER
      Futures socket smoke — instrument=#{@instrument} candle=#{@candle_interval} orderbook=@#{@orderbook_depth}-futures
      Public: candlestick / depth-snapshot / new-trade / price-change / #{pc::CURRENT_PRICES_FUTURES_UPDATE_EVENT}
    BANNER
  end

  def subscribe_documented_public_streams!
    pc = CoinDCX::WS::PublicChannels
    book = pc.futures_order_book(instrument: @instrument, depth: @orderbook_depth)

    subscribe_public(pc.futures_candlestick(instrument: @instrument, interval: @candle_interval), "candlestick") do |p|
      line!("candlestick", p)
    end
    subscribe_public(book, "depth-snapshot") { |p| line!("depth-snapshot", summarize_book(p)) }
    subscribe_public(pc.futures_new_trade(instrument: @instrument), "new-trade") { |p| line!("new-trade", p) }
    subscribe_public(pc.futures_ltp(instrument: @instrument), "price-change") { |p| line!("price-change", p) }
    subscribe_public(pc.current_prices_futures, pc::CURRENT_PRICES_FUTURES_UPDATE_EVENT) do |p|
      throttled_line!(pc::CURRENT_PRICES_FUTURES_UPDATE_EVENT, p) { summarize_futures_prices(p) }
    end
  end

  def subscribe_private_streams_if_configured!
    priv = CoinDCX::WS::PrivateChannels
    unless private_credentials?
      puts "Private streams skipped (set COINDCX_API_KEY and COINDCX_API_SECRET for df-*, balance-update)."
      return
    end

    puts "Private: #{priv::DF_POSITION_UPDATE_EVENT}, #{priv::DF_ORDER_UPDATE_EVENT}, #{priv::BALANCE_UPDATE_EVENT}"
    @ws.subscribe_private(event_name: priv::DF_POSITION_UPDATE_EVENT) { |p| line!(priv::DF_POSITION_UPDATE_EVENT, p) }
    @ws.subscribe_private(event_name: priv::DF_ORDER_UPDATE_EVENT) { |p| line!(priv::DF_ORDER_UPDATE_EVENT, p) }
    @ws.subscribe_private(event_name: priv::BALANCE_UPDATE_EVENT) { |p| line!(priv::BALANCE_UPDATE_EVENT, p) }
  end

  def subscribe_public(channel_name, event_name, &block)
    ws.subscribe_public(channel_name: channel_name, event_name: event_name, &block)
  end

  def private_credentials?
    key = ENV["COINDCX_API_KEY"].to_s.strip
    secret = ENV["COINDCX_API_SECRET"].to_s.strip
    !key.empty? && !secret.empty?
  end

  def line!(tag, payload)
    ts = Time.now.utc.iso8601(3)
    puts "#{ts} [#{tag}] #{payload.inspect}"
  end

  def throttled_line!(tag, payload)
    tick[tag] += 1
    show = verbose || (tick[tag] % throttle).zero?
    return unless show

    summary = block_given? ? yield : payload
    line!(tag, summary)
  end

  def summarize_book(payload)
    return payload unless payload.is_a?(Hash)

    asks = payload["asks"] || payload[:asks]
    bids = payload["bids"] || payload[:bids]
    vs = payload["vs"] || payload[:vs]
    {
      "vs" => vs,
      "ask_levels" => asks.is_a?(Hash) ? asks.size : asks&.size,
      "bid_levels" => bids.is_a?(Hash) ? bids.size : bids&.size
    }
  end

  def summarize_futures_prices(payload)
    return payload if verbose
    return payload unless payload.is_a?(Hash)

    prices = payload["prices"] || payload[:prices]
    {
      "vs" => payload["vs"] || payload[:vs],
      "ts" => payload["ts"] || payload[:ts],
      "instrument_count" => prices.is_a?(Hash) ? prices.size : nil
    }
  end

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

  def outer_connect_loop(configuration)
    attempts = 0
    loop do
      ws.connect
      attempts = 0
      puts "Connected to #{configuration.socket_base_url}. Ctrl+C to stop."
      loop { sleep 1 }
    rescue CoinDCX::Errors::SocketConnectionError => e
      attempts += 1
      sleep_seconds = [configuration.socket_reconnect_interval * (2**(attempts - 1)), 60].min
      warn("Socket connection error: #{e.message} — retrying in #{sleep_seconds}s (attempt #{attempts})")
      safe_disconnect_ws
      sleep(sleep_seconds)
    end
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
  FuturesSocketsSmoke.new.run
rescue CoinDCX::Errors::SocketAuthenticationError => e
  warn("Authentication failed: #{e.message}")
  exit 4
rescue CoinDCX::Errors::ValidationError => e
  warn("Invalid instrument or channel: #{e.message}")
  exit 2
end
