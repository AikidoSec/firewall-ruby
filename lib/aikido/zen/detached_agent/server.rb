# frozen_string_literal: true

module Aikido::Zen::DetachedAgent
  class Server
    def initialize(config: Aikido::Zen.config)
      @detached_agent_front = FrontObject.new
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
