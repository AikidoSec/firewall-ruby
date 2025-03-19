# frozen_string_literal: true

require "drb/drb"

module Aikido::Zen
  class DetachedAgent
    extend Forwardable

    def_delegators :@detached_agent_front, :middleware_installed!

    def initialize(config: Aikido::Zen.config)
      @config = config
      @detached_agent_front = DRbObject.new(nil, config.detached_agent_socket_path)
    end

    def track_request(request)
      @detached_agent_front.track_request
    end

    # Everytime a fork happens, we have to start a DRb service in a background thread
    # it will be in charge of maintaining the connection and clean up resources.
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
      @drb_server.verbose = true
    end

    def start
      until @drb_server.alive?
        @config.logger.info("server still not alive")
        sleep 0.3
      end
    end

    def stop!
      @drb_server.stop_service
    end
  end
end
