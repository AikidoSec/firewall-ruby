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
require_relative "zen/detached_agent"
require_relative "zen/middleware/check_allowed_addresses"
require_relative "zen/middleware/middleware"
require_relative "zen/middleware/request_tracker"
require_relative "zen/middleware/set_context"
require_relative "zen/outbound_connection"
require_relative "zen/outbound_connection_monitor"
require_relative "zen/runtime_settings"
require_relative "zen/rate_limiter"
require_relative "zen/scanners"
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
      check_and_handle_fork
      @collector ||= Collector.new
    end

    def self.detached_agent
      check_and_handle_fork
      @detached_agent ||= DetachedAgent::Agent.new
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
      collector.track_request
    end

    def self.track_discovered_route(request)
      collector.track_route(request)
    end

    # Tracks a network connection made to an external service.
    #
    # @param connection [Aikido::Zen::OutboundConnection]
    # @return [void]
    def self.track_outbound(connection)
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

    # Marks that the Zen middleware was installed properly
    # @return void
    def self.middleware_installed!
      collector.middleware_installed!
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
      @agent&.stop!
      @detached_agent_server&.stop!
    end

    # @!visibility private
    # Starts the background agent if it has not been started yet.
    def self.agent
      @agent ||= Agent.start
    end

    def self.detached_agent_server
      @detached_agent_server ||= DetachedAgent::Server.start!
    end

    class << self
      # `agent` and `detached_agent` are started on the first method call.
      # A mutex controls thread execution to prevent multiple attempts.
      LOCK = Mutex.new

      def start!
        @pid = Process.pid
        LOCK.synchronize do
          agent
          detached_agent_server
        end
      end

      def check_and_handle_fork
        if has_forked
          @detached_agent&.handle_fork
        end
      end

      def has_forked
        pid_changed = Process.pid != @pid
        @pid = Process.pid
        pid_changed
      end
    end
  end
end
