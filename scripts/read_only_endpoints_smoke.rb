#!/usr/bin/env ruby
# frozen_string_literal: true

# Smoke-test every REST method exposed by coindcx-client that does not create, cancel,
# edit orders, move funds, or change leverage / margin / position state.
#
# Usage (from repository root):
#   bundle exec ruby scripts/read_only_endpoints_smoke.rb
#
# If `bundle exec` prints Gem::Platform "already initialized constant" warnings (often with RVM +
# an older Bundler), they come from Bundler before this file loads. They are harmless. To hide them:
#   RUBYOPT=-W0 bundle exec ruby scripts/read_only_endpoints_smoke.rb
#
# Credentials: set COINDCX_API_KEY and COINDCX_API_SECRET in the environment, or define
# them in a .env file next to this script's parent directory (repository root).
#
# Optional:
#   COINDCX_SAMPLE_PAIR — spot/futures pair (default B-BTC_USDT)
#   COINDCX_SPOT_ORDER_ID — if set, calls spot fetch_status for this id
#   COINDCX_SPOT_ORDER_IDS — comma-separated ids for fetch_statuses
#   COINDCX_MARGIN_ORDER_ID — if set, calls margin fetch for this id

require "logger"
require "time"
require_relative "../lib/coindcx"

$stdout.sync = true

class ReadOnlyEndpointsSmoke
  DEFAULT_PAIR = "B-BTC_USDT"
  MARGIN_CURRENCY = "USDT"

  def initialize
    @pair = ENV.fetch("COINDCX_SAMPLE_PAIR", DEFAULT_PAIR)
    @now = Time.now.to_i
    @from = @now - 3600
    @now_ms = (Time.now.to_f * 1000).to_i
    @from_ms = @now_ms - (60 * 60 * 1000)
    @logger = Logger.new($stdout)
    @logger.level = Logger::INFO
    @failures = 0
    @skipped = 0
  end

  def run
    load_dotenv_if_present
    configure_gem
    client = CoinDCX.client
    banner("Public market data (unauthenticated)")
    run_public(client)
    banner("User (read-only)")
    run_user(client)
    banner("Spot orders (read-only)")
    run_spot_read(client)
    banner("Margin orders (read-only)")
    run_margin_read(client)
    banner("Futures market data (unauthenticated)")
    run_futures_market(client)
    banner("Futures orders (read-only)")
    run_futures_orders_read(client)
    banner("Futures positions (read-only)")
    run_futures_positions_read(client)
    banner("Futures wallets (read-only)")
    run_futures_wallets_read(client)
    summary
  end

  private

  attr_reader :pair, :now, :from, :now_ms, :from_ms, :logger, :failures, :skipped

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
      config.api_key = ENV.fetch("COINDCX_API_KEY")
      config.api_secret = ENV.fetch("COINDCX_API_SECRET")
      config.logger = logger
    end
  end

  def banner(title)
    puts "\n=== #{title} ==="
  end

  def hit(name)
    print "#{name} ... "
    result = yield
    puts "OK (#{summarize(result)})"
  rescue StandardError => e
    @failures += 1
    puts "FAIL (#{e.class}: #{e.message})"
  end

  def skip(name, reason)
    @skipped += 1
    puts "#{name} ... SKIP (#{reason})"
  end

  def parse_comma_separated_env(key)
    raw = ENV.fetch(key, nil)
    return [] if raw.nil? || raw.strip.empty?

    raw.split(",").map(&:strip).reject(&:empty?)
  end

  def summarize(value)
    case value
    when Array
      "#{value.size} items"
    when Hash
      "#{value.size} keys"
    else
      value.class.name
    end
  end

  def run_public(client)
    md = client.public.market_data
    hit("public.market_data.list_tickers") { md.list_tickers }
    hit("public.market_data.list_markets") { md.list_markets }
    hit("public.market_data.list_market_details") { md.list_market_details }
    hit("public.market_data.list_trades") { md.list_trades(pair: pair, limit: 5) }
    hit("public.market_data.fetch_order_book") { md.fetch_order_book(pair: pair) }
    hit("public.market_data.list_candles") do
      md.list_candles(pair: pair, interval: "1m", start_time: from_ms, end_time: now_ms, limit: 5)
    end
  end

  def run_user(client)
    acc = client.user.accounts
    hit("user.accounts.list_balances") { acc.list_balances }
    hit("user.accounts.fetch_info") { acc.fetch_info }
  end

  def run_spot_read(client)
    orders = client.spot.orders
    hit("spot.orders.list_active") { orders.list_active }
    hit("spot.orders.count_active") { orders.count_active }
    hit("spot.orders.list_trade_history") { orders.list_trade_history }

    if ENV["COINDCX_SPOT_ORDER_ID"]
      hit("spot.orders.fetch_status") { orders.fetch_status(id: ENV.fetch("COINDCX_SPOT_ORDER_ID")) }
    else
      skip("spot.orders.fetch_status", "set COINDCX_SPOT_ORDER_ID to exercise")
    end

    ids = parse_comma_separated_env("COINDCX_SPOT_ORDER_IDS")
    if ids.any?
      hit("spot.orders.fetch_statuses") { orders.fetch_statuses(ids: ids) }
    else
      skip("spot.orders.fetch_statuses", "set COINDCX_SPOT_ORDER_IDS (comma-separated) to exercise")
    end
  end

  def run_margin_read(client)
    m = client.margin.orders
    hit("margin.orders.list") { m.list }
    if ENV["COINDCX_MARGIN_ORDER_ID"]
      hit("margin.orders.fetch") { m.fetch(id: ENV.fetch("COINDCX_MARGIN_ORDER_ID")) }
    else
      skip("margin.orders.fetch", "set COINDCX_MARGIN_ORDER_ID to exercise")
    end
  end

  def run_futures_market(client)
    md = client.futures.market_data
    hit("futures.market_data.list_active_instruments") do
      md.list_active_instruments(margin_currency_short_names: [MARGIN_CURRENCY])
    end
    hit("futures.market_data.fetch_instrument") do
      md.fetch_instrument(pair: pair, margin_currency_short_name: MARGIN_CURRENCY)
    end
    hit("futures.market_data.list_trades") { md.list_trades(pair: pair) }
    hit("futures.market_data.fetch_order_book") { md.fetch_order_book(instrument: pair, depth: 50) }
    hit("futures.market_data.list_candlesticks") do
      md.list_candlesticks(pair: pair, from: from_ms, to: now_ms, resolution: "1m")
    end
  end

  def run_futures_orders_read(client)
    hit("futures.orders.list") { client.futures.orders.list }
  end

  def run_futures_positions_read(client)
    p = client.futures.positions
    hit("futures.positions.list") { p.list }
    hit("futures.positions.list_transactions") { p.list_transactions }
    hit("futures.positions.fetch_cross_margin_details") { p.fetch_cross_margin_details }
  end

  def run_futures_wallets_read(client)
    w = client.futures.wallets
    hit("futures.wallets.fetch_details") { w.fetch_details }
    hit("futures.wallets.list_transactions") { w.list_transactions(page: 1, size: 100) }
  end

  def summary
    puts "\n=== Summary ==="
    puts "Failures: #{failures}"
    puts "Skipped (optional id-based calls): #{skipped}"
    exit(1) if failures.positive?
  end
end

ReadOnlyEndpointsSmoke.new.run if $PROGRAM_NAME == __FILE__
