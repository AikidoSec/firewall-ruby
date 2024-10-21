# frozen_string_literal: true

require_relative "zen/version"
require_relative "zen/errors"
require_relative "zen/actor"
require_relative "zen/config"
require_relative "zen/system_info"
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

    # Gets information about the current system configuration, which is sent to
    # the server along with any events.
    def self.system_info
      @system_info ||= SystemInfo.new
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

    # Track statistics about the result of a Sink's scan, and report it as an
    # Attack if one is detected.
    #
    # @param scan [Aikido::Zen::Scan]
    # @return [void]
    # @raise [Aikido::Zen::UnderAttackError] if the scan detected an Attack
    #   and blocking_mode is enabled.
    def self.track_scan(scan)
      agent.stats.add_scan(scan)
      agent.handle_attack(scan.attack) if scan.attack?
    end

    # Track statistics about an HTTP request the app is handling.
    #
    # @param context [Aikido::Zen::Request]
    # @return [void]
    def self.track_request(request)
      agent.stats.add_request(request)
    end

    # Tracks a network connection made to an external service.
    #
    # @param connection [Aikido::Zen::OutboundConnection]
    # @return [void]
    def self.track_outbound(connection)
      agent.stats.add_outbound(connection)
    end

    # Track the user making the current request.
    #
    # @param (see Aikido::Zen.Actor)
    # @return [void]
    def self.track_user(user)
      actor = Aikido::Zen::Actor(user)

      if actor
        agent.stats.add_user(actor)
      else
        id_attr, name_attr = config.user_attribute_mappings.values_at(:id, :name)
        config.logger.warn(format(<<~LOG, obj: user, id: id_attr, name: name_attr))
          Incompatible object sent to Aikido::Zen.track_user: %<obj>p

          The object must satisfy one of the following:

          * Implement #to_aikido_actor
          * Implement #to_model and have %<id>p and %<name>p attributes
          * Be a Hash with :id (or "id") and, optionally, :name (or "name") keys
        LOG
      end
    end

    # Starts the background threads that keep the agent running.
    #
    # @return [void]
    def self.initialize!
      @agent ||= Agent.new
      @agent.start!
    end

    # Stop any background threads.
    def self.stop!
      @agent&.stop!
    end

    # @return [Aikido::Zen::RuntimeSettings] the firewall configuration sourced
    #   from your Aikido dashboard. This is periodically polled for updates.
    def self.runtime_settings
      @runtime_settings ||= RuntimeSettings.new
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

    private_class_method def self.agent
      # We shouldn't start collecting data before we even initialize the agent,
      # but might as well make sure we have a @agent going to report to.
      @agent or initialize!
      @agent
    end
  end
end
