# frozen_string_literal: true

require_relative "firewall/version"
require_relative "agent/config"
require_relative "agent/info"
require_relative "agent/runner"
require_relative "agent/api_client"
require_relative "agent/context"
require_relative "agent/set_context"
require_relative "agent/outbound_connection"
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
    def self.track_scan(scan)
      runner.stats.add_scan(scan)
      runner.handle_attack(scan.attack) if scan.attack?
    end

    # Track statistics about an HTTP request the app is handling.
    #
    # @param context [Aikido::Agent::Request]
    # @return [void]
    def self.track_request(request)
      runner.stats.add_request(request)
    end

    # Tracks a network connection made to an external service.
    #
    # @param connection [Aikido::Agent::OutboundConnection]
    # @return [void]
    def self.track_outbound(connection)
      runner.stats.add_outbound(connection)
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

    private_class_method def self.runner
      # We shouldn't start collecting data before we even initialize the runner,
      # but might as well make sure we have a @runner going to report to.
      @runner or initialize!
      @runner
    end
  end
end
