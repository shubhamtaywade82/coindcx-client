# frozen_string_literal: true

module CoinDCX
  class Client
    def initialize(configuration:)
      @configuration = configuration
      @http_client = Transport::HttpClient.new(configuration: configuration)
    end

    attr_reader :configuration

    def public
      @public ||= REST::Public::Facade.new(http_client: @http_client)
    end

    def spot
      @spot ||= REST::Spot::Facade.new(http_client: @http_client)
    end

    def margin
      @margin ||= REST::Margin::Facade.new(http_client: @http_client)
    end

    def user
      @user ||= REST::User::Facade.new(http_client: @http_client)
    end

    def transfers
      @transfers ||= REST::Transfers::Facade.new(http_client: @http_client)
    end

    def futures
      @futures ||= REST::Futures::Facade.new(http_client: @http_client)
    end

    def funding
      @funding ||= REST::Funding::Facade.new(http_client: @http_client)
    end

    def ws
      @ws ||= WS::SocketIOClient.new(configuration: configuration)
    end
  end
end
