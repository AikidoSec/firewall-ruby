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
require_relative "zen/middleware/middleware"
require_relative "zen/middleware/fork_detector"
require_relative "zen/middleware/set_context"
require_relative "zen/middleware/check_allowed_addresses"
require_relative "zen/middleware/request_tracker"
require_relative "zen/middleware/attack_wave_protector"
require_relative "zen/outbound_connection"
require_relative "zen/outbound_connection_monitor"
require_relative "zen/runtime_settings"
require_relative "zen/rate_limiter"
require_relative "zen/attack_wave"
require_relative "zen/scanners"

module Aikido
  module Zen
    # Enable protection. Until this method is called no sinks are loaded
    # and the Aikido Agent does not start.
    #
    # This method should be called only once, in the application after the
    # initialization process is complete.
    #
    # @return [void]
    def self.protect!
      if config.disabled?
        config.logger.warn("Zen has been disabled and will not run.")
        return
      end

      unless load_sources! && load_sinks!
        config.logger.warn("Zen could not find any supported libraries or frameworks. Visit https://github.com/AikidoSec/firewall-ruby for more information.")
        return
      end

      middleware_installed!
    end

    # @!visibility private
    # Returns whether the loaded gem specification satisfies the listed requirements.
    #
    # Returns false if the gem specification is not loaded.
    #
    # @param name [String] the gem name
    # @param requirements [Array<String>] a variable number of gem requirement strings
    #
    # @return [Boolean] true if the gem specification is loaded and all gem requirements are satisfied
    def self.satisfy(name, *requirements)
      spec = Gem.loaded_specs[name]

      return false if spec.nil?

      Gem::Requirement.new(*requirements).satisfied_by?(spec.version)
    end

    # @return [Aikido::Zen::Config] the agent configuration.
    def self.config
      @config ||= Config.new
    end

    # @return [Aikido::Zen::RuntimeSettings] the firewall configuration sourced
    #   from your Aikido dashboard. This is periodically polled for updates.
    def self.runtime_settings
      @runtime_settings ||= RuntimeSettings.new
    end

    def self.runtime_settings=(settings)
      @runtime_settings = settings
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
      collector.track_request
    end

    # Track statistics about an attack wave the app is handling.
    #
    # @param attack_wave [Aikido::Zen::Events::AttackWave]
    # @return [void]
    def self.track_attack_wave(attack_wave)
      collector.track_attack_wave
    end

    # Track statistics about a route that the app has discovered.
    #
    # @param request [Aikido::Zen::Request]
    # @return [void]
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

    # Align with other Zen implementations, while keeping internal consistency.
    class << self
      alias_method :set_user, :track_user
    end

    # Marks that the Zen middleware was installed properly
    # @return void
    def self.middleware_installed!
      collector.middleware_installed!
    end

    # @return [Aikido::Zen::AttackWave::Detector] the attack wave detector.
    def self.attack_wave_detector
      @attack_wave_detector ||= AttackWave::Detector.new
    end

    # @!visibility private
    # Load all sources.
    #
    # @return [Boolean] true if any sources were loaded
    def self.load_sources!
      if Aikido::Zen.satisfy("rails", ">= 7.0")
        require_relative "zen/rails_engine"

        return true
      end

      false
    end

    # @!visibility private
    # Load all sinks.
    #
    # @return [Boolean] true if any sinks were loaded
    def self.load_sinks!
      require_relative "zen/sinks"

      !Aikido::Zen::Sinks.registry.empty?
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

    def self.detached_agent
      @detached_agent ||= DetachedAgent::Agent.new
    end

    def self.detached_agent_server
      @detached_agent_server ||= DetachedAgent::Server.start
    end

    class << self
      # `agent` and `detached_agent` are started on the first method call.
      # A mutex controls thread execution to prevent multiple attempts.
      LOCK = Mutex.new

      def start!
        return unless start?

        @pid = Process.pid

        LOCK.synchronize do
          agent
          detached_agent_server
        end
      end

      def start?
        !config.api_token.nil? ||
          config.blocking_mode? ||
          config.debugging?
      end

      def check_and_handle_fork
        handle_fork if forked?
      end

      def forked?
        pid_changed = Process.pid != @pid
        @pid = Process.pid
        pid_changed
      end

      def handle_fork
        @detached_agent&.handle_fork
      end
    end

    # @!visibility private
    # Returns the stack trace trimmed to where execution last entered Zen.
    #
    # @return [String]
    def self.clean_stack_trace
      stack_trace = caller_locations

      spec = Gem.loaded_specs["aikido-zen"]

      # Only trim stack frames from .../lib/aikido/zen/ in the aikido-zen gem,
      # so calls in sample apps are preserved.
      lib_path_start = File.expand_path(File.join(spec.full_gem_path, "lib", "aikido", "zen")) + File::SEPARATOR

      index = stack_trace.index { |frame| !File.expand_path(frame.path).start_with?(lib_path_start) }
      stack_trace = stack_trace[index..] if index

      stack_trace.map(&:to_s).join("\n")
    end
  end
end
