# frozen_string_literal: true

require_relative "firewall/version"
require_relative "agent/config"
require_relative "agent/info"
require_relative "agent/runner"
require_relative "agent/api_client"
require_relative "agent/current_request"
require_relative "agent/rails_engine" if defined?(::Rails)

module Aikido
  module Agent
    VERSION = Firewall::VERSION

    # @return [Aikido::Agent::Config] the agent configuration.
    def self.config
      @config ||= Config.new
    end

    # Gets information about the current configuration of the agent, which is
    # sent to the server along with any events.
    def self.info
      @info ||= Info.new
    end

    # Starts the background threads that keep the agent running.
    #
    # @return [Aikido::Agent::Runner]
    def self.initialize!
      @runner ||= Runner.new
      @runner.start!
    end

    # Stop any background threads.
    def self.stop!
      @runner&.stop!
    end
  end
end
