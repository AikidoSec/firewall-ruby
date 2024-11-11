# frozen_string_literal: true

require_relative "zen/version"
require_relative "zen/errors"
require_relative "zen/actor"
require_relative "zen/config"
require_relative "zen/collector"
require_relative "zen/system_info"
require_relative "zen/worker"
require_relative "zen/agent"
require_relative "zen/api_client"
require_relative "zen/context"
require_relative "zen/middleware/set_context"
require_relative "zen/outbound_connection"
require_relative "zen/outbound_connection_monitor"
require_relative "zen/runtime_settings"
require_relative "zen/rate_limiter"
require_relative "zen/scanners"
require_relative "zen/middleware/check_allowed_addresses"
require_relative "zen/rails_engine" if defined?(::Rails)

module Aikido
  module Zen
    # @return [Aikido::Zen::Config] the agent configuration.
    def self.config
      @config ||= Config.new
    end

    # @return [Aikido::Zen::RuntimeSettings] the firewall configuration sourced
    #   from your Aikido dashboard. This is periodically polled for updates.
    def self.runtime_settings
      @runtime_settings ||= RuntimeSettings.new
    end

    # Gets information about the current system configuration, which is sent to
    # the server along with any events.
    def self.system_info
      @system_info ||= SystemInfo.new
    end

    # Manages runtime metrics extracted from your app, which are uploaded to the
    # Aikido servers if configured to do so.
    def self.collector
      @collector ||= Collector.new
    end

    # Gets the current context object that holds all information about the
    # current request.
    #
    # @return [Aikido::Zen::Context, nil]
    def self.current_context
      Thread.current[:_aikido_current_context_]
    end

    # Sets the current context object that holds all information about the
    # current request, or +nil+ to clear the current context.
    #
    # @param context [Aikido::Zen::Context, nil]
    # @return [Aikido::Zen::Context, nil]
    def self.current_context=(context)
      Thread.current[:_aikido_current_context_] = context
    end

    # Track statistics about an HTTP request the app is handling.
    #
    # @param request [Aikido::Zen::Request]
    # @return [void]
    def self.track_request(request)
      autostart
      collector.track_request(request)
    end

    # Tracks a network connection made to an external service.
    #
    # @param connection [Aikido::Zen::OutboundConnection]
    # @return [void]
    def self.track_outbound(connection)
      autostart
      collector.track_outbound(connection)
    end

    # Track statistics about the result of a Sink's scan, and report it as
    # an Attack if one is detected.
    #
    # @param scan [Aikido::Zen::Scan]
    # @return [void]
    # @raise [Aikido::Zen::UnderAttackError] if the scan detected an Attack
    #   and blocking_mode is enabled.
    def self.track_scan(scan)
      autostart
      collector.track_scan(scan)
      agent.handle_attack(scan.attack) if scan.attack?
    end

    # Track the user making the current request.
    #
    # @param (see Aikido::Zen.Actor)
    # @return [void]
    def self.track_user(user)
      return if config.disabled?

      if (actor = Aikido::Zen::Actor(user))
        autostart
        collector.track_user(actor)
        current_context.request.actor = actor if current_context
      else
        config.logger.warn(format(<<~LOG, obj: user))
          Incompatible object sent to track_user: %<obj>p

          The object must either implement #to_aikido_actor, or be a Hash with
          an :id (or "id") and, optionally, a :name (or "name") key.
        LOG
      end
    end

    # Load all sinks matching libraries loaded into memory. This method should
    # be called after all other dependencies have been loaded into memory (i.e.
    # at the end of the initialization process).
    #
    # If a new gem is required, this method can be called again safely.
    #
    # @return [void]
    def self.load_sinks!
      require_relative "zen/sinks"
    end

    # @!visibility private
    # Stop any background threads.
    def self.stop!
      agent&.stop!
    end

    # @!visibility private
    # Starts the background agent if it has not been started yet.
    def self.agent
      @agent ||= Agent.start
    end

    class << self
      alias_method :autostart, :agent
    end
  end
end
