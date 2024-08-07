# frozen_string_literal: true

require_relative "firewall/version"
require_relative "agent/config"

module Aikido
  module Agent
    VERSION = Firewall::VERSION

    # @return [Config] the agent configuration.
    def self.config
      @config ||= Config.new
    end
  end
end

require_relative "agent/api_client"
require_relative "agent/current_request"
require_relative "agent/rails_engine" if defined?(::Rails)
