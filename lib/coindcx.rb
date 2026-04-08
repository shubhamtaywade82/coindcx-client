# frozen_string_literal: true

require_relative "coindcx/version"
require_relative "coindcx/utils/payload"
require_relative "coindcx/errors/base_error"
require_relative "coindcx/logging/null_logger"
require_relative "coindcx/contracts/channel_name"
require_relative "coindcx/contracts/socket_backend"
require_relative "coindcx/models/base_model"

Dir[File.join(__dir__, "coindcx/models/*.rb")].sort.each do |file|
  require file unless file.end_with?("base_model.rb")
end

require_relative "coindcx/auth/signer"
require_relative "coindcx/transport/rate_limit_registry"
require_relative "coindcx/transport/retry_policy"
require_relative "coindcx/transport/http_client"
require_relative "coindcx/rest/base_resource"

Dir[File.join(__dir__, "coindcx/rest/**/*.rb")].sort.each do |file|
  require file unless file.end_with?("base_resource.rb")
end

Dir[File.join(__dir__, "coindcx/ws/**/*.rb")].sort.each do |file|
  require file
end

require_relative "coindcx/configuration"
require_relative "coindcx/client"

module CoinDCX
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def client
      Client.new(configuration: configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
