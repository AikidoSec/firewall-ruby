# frozen_string_literal: true

require "drb/drb"

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

    # Everytime a fork happens, we have to start a DRb service in a background thread.
    # It will be in charge of maintaining the connection and clean up resources.
    def handle_fork
      DRb.start_service
    end
  end

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
      @config = config
      @detached_agent_front = DetachedAgentFront.new
      @drb_server = DRb.start_service(config.detached_agent_socket_path, @detached_agent_front)
      @drb_server.verbose = @config.logger.debug?
      @max_attempts = 10
    end

    def start
      attempts = 0
      until @drb_server.alive?
        @config.logger.info("DRb Server still not alive. #{@max_attempts - attempts} attempts remaining")
        sleep 0.1
        attempts += 1
        raise DetachedAgentError.new("Impossible to start the dRB server (socket=#{@config.detached_agent_socket_path})") if attempts == @max_attempts
      end
    end

    def stop!
      @drb_server.stop_service
      DRb.stop_service
    end
  end
end
