# frozen_string_literal: true

require "drb/drb"
require "drb/unix"

module Aikido::Zen
  # It's possible to use `extend Forwardable` here for one-line forward calls to the
  # @detached_agent_front object. Unfortunately, the methods to be called are
  # created at runtime by `DRbObject`, which leads to an ugly warning about
  # private methods after the delegator is bound.
  class DetachedAgent
    def initialize(config: Aikido::Zen.config)
      @config = config
      @detached_agent_front = DRbObject.new_with_uri(config.detached_agent_socket_path)
    end

    def track_request(request)
      @detached_agent_front.track_request
    end

    def middleware_installed!
      @detached_agent_front.middleware_installed!
    end

    # Every time a fork occurs (a new child process is created), we need to start
    # a DRb service in a background thread within the child process. This service
    # will manage the connection and handle resource cleanup.
    def handle_fork
      DRb.start_service
    end
  end

  # dRB Front object that will be used to access the collector.
  class DetachedAgentFront
    extend Forwardable

    def_delegators :@collector, :middleware_installed!, :track_request

    def initialize(config: Aikido::Zen.config, collector: Aikido::Zen.collector)
      @config = config
      @collector = collector
    end
  end

  class DetachedAgentServer
    def initialize(config: Aikido::Zen.config)
      @detached_agent_front = DetachedAgentFront.new
      @drb_server = DRb.start_service(config.detached_agent_socket_path, @detached_agent_front)

      # We don't want to see drb logs unless in debug mode
      @drb_server.verbose = config.logger.debug?
    end

    def alive?
      @drb_server.alive?
    end

    def stop!
      @drb_server.stop_service
      DRb.stop_service
    end

    class << self
      def start!
        Aikido::Zen.config.logger.debug("Starting DRb Server...")
        max_attempts = 10
        @server = new

        attempts = 0
        until @server.alive?
          Aikido::Zen.config.logger.info("DRb Server still not alive. #{max_attempts - attempts} attempts remaining")
          sleep 0.1
          attempts += 1
          raise DetachedAgentError.new("Impossible to start the dRB server (socket=#{Aikido::Zen.config.detached_agent_socket_path})") \
            if attempts == max_attempts
        end

        @server
      end
    end
  end
end
