#!/usr/bin/env ruby
# frozen_string_literal: true

# Connects to CoinDCX Socket.IO and subscribes several futures public channels at once.
#
# Usage (from repository root):
#   bundle exec ruby scripts/futures_ws_subscription_smoke.rb
#
# Environment:
#   COINDCX_WS_INSTRUMENTS — comma-separated pair codes (default: auto-pick from public REST)
#   COINDCX_WS_INSTRUMENT_COUNT — when auto-picking, how many (default 3)
#   COINDCX_WS_WAIT_SECONDS — max seconds to wait for price ticks (default 45)
#   COINDCX_WS_MARGIN_CURRENCIES — comma-separated, passed to active_instruments (default USDT)
#
# API keys are optional for public futures streams; set COINDCX_API_KEY / COINDCX_API_SECRET
# if you also want private streams (see COINDCX_WS_PRIVATE).
#
#   COINDCX_WS_PRIVATE=1 — after public subs, also subscribe to private order-update (requires keys)

require "logger"
require_relative "../lib/coindcx"

$stdout.sync = true

class FuturesPublicWsTester
  DEFAULT_WAIT_SECONDS = 45
  DEFAULT_AUTO_COUNT = 3
  PRICE_EVENT = "price-change"
  TRADE_EVENT = "new-trade"

  def initialize
    @logger = Logger.new($stdout)
    @logger.level = Logger::INFO
    @wait_seconds = Integer(ENV.fetch("COINDCX_WS_WAIT_SECONDS", DEFAULT_WAIT_SECONDS))
    @mutex = Mutex.new
    @price_counts = Hash.new(0)
    @trade_counts = Hash.new(0)
    @ws = nil
  end

  def run
    load_dotenv_if_present
    configure_gem
    instruments = resolve_instruments
    if instruments.empty?
      warn("No instruments to subscribe (set COINDCX_WS_INSTRUMENTS or check REST active_instruments).")
      exit 2
    end

    client = CoinDCX.client
    @ws = client.ws
    install_shutdown_hooks

    puts "Connecting to #{client.configuration.socket_base_url} ..."
    @ws.connect
    puts "Connected. Subscribing #{instruments.size} instrument(s) × 2 channels (prices-futures + trades-futures)."

    subscribe_all(instruments)
    subscribe_private_optional

    deadline = Time.now + @wait_seconds
    until Time.now >= deadline
      break if price_targets_met?(instruments)

      sleep 0.5
    end

    print_summary(instruments)
    @ws.disconnect

    exit(all_prices_seen?(instruments) ? 0 : 1)
  end

  private

  attr_reader :logger, :mutex, :price_counts, :trade_counts, :ws, :wait_seconds

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
    end
  end

  def resolve_instruments
    raw = ENV.fetch("COINDCX_WS_INSTRUMENTS", "").strip
    if raw.empty?
      auto_pick_instruments
    else
      raw.split(",").map(&:strip).reject(&:empty?)
    end
  end

  def auto_pick_instruments
    count = Integer(ENV.fetch("COINDCX_WS_INSTRUMENT_COUNT", DEFAULT_AUTO_COUNT))
    currencies = parse_comma_list("COINDCX_WS_MARGIN_CURRENCIES", %w[USDT])
    rows = CoinDCX.client.futures.market_data.list_active_instruments(margin_currency_short_names: currencies)
    Array(rows).filter_map { |row| row["pair"] || row[:pair] }.uniq.first(count)
  end

  def parse_comma_list(key, default)
    raw = ENV.fetch(key, nil)
    return default if raw.nil? || raw.strip.empty?

    raw.split(",").map(&:strip).reject(&:empty?)
  end

  def subscribe_all(instruments)
    pc = CoinDCX::WS::PublicChannels
    instruments.each do |instrument|
      price_channel = pc.futures_price_stats(instrument: instrument)
      trade_channel = pc.futures_new_trade(instrument: instrument)

      ws.subscribe_public(channel_name: price_channel, event_name: PRICE_EVENT) do |_payload|
        bump(:price, instrument)
      end
      ws.subscribe_public(channel_name: trade_channel, event_name: TRADE_EVENT) do |_payload|
        bump(:trade, instrument)
      end

      puts "  join #{price_channel} → #{PRICE_EVENT}"
      puts "  join #{trade_channel} → #{TRADE_EVENT}"
    end
  end

  def subscribe_private_optional
    return unless truthy_env?("COINDCX_WS_PRIVATE")

    ws.subscribe_private(event_name: CoinDCX::WS::PrivateChannels::ORDER_UPDATE_EVENT) do |payload|
      puts "[private order-update] #{payload.inspect[0, 200]}..."
    end
    puts "  join private coindcx → #{CoinDCX::WS::PrivateChannels::ORDER_UPDATE_EVENT}"
  rescue CoinDCX::Errors::AuthenticationError => e
    warn("Private WS not started: #{e.message}")
  end

  def truthy_env?(key)
    %w[1 true yes on].include?(ENV.fetch(key, "").downcase)
  end

  def bump(kind, instrument)
    mutex.synchronize do
      case kind
      when :price
        price_counts[instrument] += 1
      when :trade
        trade_counts[instrument] += 1
      end
    end
  end

  def price_targets_met?(instruments)
    instruments.all? { |i| price_counts[i].positive? }
  end

  def all_prices_seen?(instruments)
    price_targets_met?(instruments)
  end

  def print_summary(instruments)
    puts "\n=== Futures WS summary (#{wait_seconds}s window) ==="
    instruments.each do |i|
      p = price_counts[i]
      t = trade_counts[i]
      status = p.positive? ? "price OK (#{p} msgs)" : "MISSING price-change"
      puts "#{i}: #{status}; new-trade: #{t} msgs"
    end
    puts "\nCoinDCX docs: #{PRICE_EVENT} on @prices-futures, #{TRADE_EVENT} on @trades-futures."
    puts "Low-liquidity instruments may not emit trades; price ticks are required for exit 0."
  end

  def install_shutdown_hooks
    socket_client = @ws
    %w[INT TERM].each do |sig|
      Signal.trap(sig) do
        warn("\nInterrupted; disconnecting.")
        socket_client&.disconnect
        exit 130
      end
    end
  end
end

begin
  FuturesPublicWsTester.new.run
rescue CoinDCX::Errors::SocketConnectionError => e
  warn("Socket connection failed: #{e.message}")
  exit 3
rescue CoinDCX::Errors::ValidationError => e
  warn("Invalid instrument or channel: #{e.message}")
  exit 2
end
