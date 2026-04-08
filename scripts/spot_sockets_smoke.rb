#!/usr/bin/env ruby
# frozen_string_literal: true

# Subscribes to CoinDCX **Spot** WebSocket channels from the public API docs (public + optional private).
# One process, one Socket.IO connection, multiple `join`s — same pattern as `futures_stream_eth_sol.rb`.
#
# Usage (repo root):
#   bundle exec ruby scripts/spot_sockets_smoke.rb
#
# Environment:
#   COINDCX_PAIR              — spot pair from markets API (default: B-BTC_USDT)
#   COINDCX_CANDLE_INTERVAL   — e.g. 1m, 5m, 15m (default: 1m)
#   COINDCX_ORDERBOOK_DEPTH   — 10, 20, or 50 (default: 20)
#   COINDCX_CURRENT_PRICES_IV — 1s or 10s (default: 10s)
#   COINDCX_API_KEY / COINDCX_API_SECRET — if both set, also subscribes to private `coindcx` channel
#   COINDCX_SPOT_VERBOSE      — set to 1 to print full payloads for noisy feeds (current prices / stats)
#   COINDCX_SPOT_THROTTLE     — print every Nth message for prices + priceStats (default: 6)
#
# WebSocket blocks receive a single coalesced payload (Socket.IO multi-arg frames are merged by the client).
#
require "logger"
require "time"
require_relative "../lib/coindcx"

$stdout.sync = true

class SpotSocketsSmoke
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
    @pair = ENV.fetch("COINDCX_PAIR", "B-BTC_USDT").strip
    @candle_interval = ENV.fetch("COINDCX_CANDLE_INTERVAL", "1m").strip
    @orderbook_depth = Integer(ENV.fetch("COINDCX_ORDERBOOK_DEPTH", "20"))
    @prices_interval = ENV.fetch("COINDCX_CURRENT_PRICES_IV", "10s").strip
    @throttle = Integer(ENV.fetch("COINDCX_SPOT_THROTTLE", "6"))
    @verbose = %w[1 true yes].include?(ENV.fetch("COINDCX_SPOT_VERBOSE", "").downcase)
  end

  def print_banner
    puts <<~BANNER
      Spot socket smoke — pair=#{@pair} candle=#{@candle_interval} orderbook=@#{@orderbook_depth} currentPrices=@#{@prices_interval}
      Public: candlestick / depth-snapshot+update / new-trade / price-change / currentPrices@spot#update / priceStats@spot#update
    BANNER
  end

  def subscribe_documented_public_streams!
    pc = CoinDCX::WS::PublicChannels
    book = pc.order_book(pair: @pair, depth: @orderbook_depth)

    subscribe_public(pc.candlestick(pair: @pair, interval: @candle_interval), "candlestick") do |p|
      line!("candlestick", p)
    end
    subscribe_public(book, "depth-snapshot") { |p| line!("depth-snapshot", summarize_book(p)) }
    subscribe_public(book, "depth-update") { |p| line!("depth-update", summarize_book(p)) }
    subscribe_public(pc.new_trade(pair: @pair), "new-trade") { |p| line!("new-trade", p) }
    subscribe_public(pc.price_stats(pair: @pair), "price-change") { |p| line!("price-change", p) }
    subscribe_public(pc.current_prices_spot(interval: @prices_interval), pc::CURRENT_PRICES_SPOT_UPDATE_EVENT) do |p|
      throttled_line!("currentPrices@spot#update", p) { summarize_prices(p) }
    end
    subscribe_public(pc.price_stats_spot, pc::PRICE_STATS_SPOT_UPDATE_EVENT) do |p|
      throttled_line!("priceStats@spot#update", p) { summarize_stats(p) }
    end
  end

  def subscribe_private_streams_if_configured!
    priv = CoinDCX::WS::PrivateChannels
    unless private_credentials?
      puts "Private streams skipped (set COINDCX_API_KEY and COINDCX_API_SECRET to enable)."
      return
    end

    puts "Private: balance-update, order-update, trade-update (channel coindcx)"
    @ws.subscribe_private(event_name: priv::BALANCE_UPDATE_EVENT) { |p| line!("balance-update", p) }
    @ws.subscribe_private(event_name: priv::ORDER_UPDATE_EVENT) { |p| line!("order-update", p) }
    @ws.subscribe_private(event_name: priv::TRADE_UPDATE_EVENT) { |p| line!("trade-update", p) }
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

  def summarize_prices(payload)
    return payload if verbose
    return payload unless payload.is_a?(Hash)

    prices = payload["prices"] || payload[:prices]
    {
      "vs" => payload["vs"] || payload[:vs],
      "ts" => payload["ts"] || payload[:ts],
      "pair_count" => prices.is_a?(Hash) ? prices.size : nil
    }
  end

  def summarize_stats(payload)
    return payload if verbose
    return payload unless payload.is_a?(Hash)

    stats = payload["stats"] || payload[:stats]
    {
      "vs" => payload["vs"] || payload[:vs],
      "ts" => payload["ts"] || payload[:ts],
      "symbol_count" => stats.is_a?(Hash) ? stats.size : nil
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
  SpotSocketsSmoke.new.run
rescue CoinDCX::Errors::SocketAuthenticationError => e
  warn("Authentication failed: #{e.message}")
  exit 4
rescue CoinDCX::Errors::ValidationError => e
  warn("Invalid pair/channel: #{e.message}")
  exit 2
end
