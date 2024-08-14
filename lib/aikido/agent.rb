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

    # Track statistics about the result of a Sink's scan, and report it as an
    # Attack if one is detected.
    #
    # @param scan [Aikido::Firewall::Scan]
    # @return [void]
    # @raise [Aikido::Firewall::UnderAttackError] if the scan detected an Attack
    #   and blocking_mode is enabled.
    def self.track(scan)
      # We shouldn't start collecting data before we even initialize the runner,
      # but might as well make sure we have a @runner going to report to.
      @runner or initialize!
      # TODO: Implement statistics gathering
      @runner.handle_attack(scan.attack) if scan.attack?
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
