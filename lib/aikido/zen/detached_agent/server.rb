# frozen_string_literal: true

require "fileutils"

module Aikido::Zen::DetachedAgent
  class Server
    def initialize(config: Aikido::Zen.config)
      detached_agent_socket_path = config.detached_agent_socket_path

      socket_path = detached_agent_socket_path.delete_prefix("drbunix:")

      begin
        # Try to connect to the Unix domain socket.
        UNIXSocket.new(socket_path).close

        # Connection successful...
      rescue Errno::ECONNREFUSED
        # Remove the residual Unix domain socket.
        FileUtils.rm_f(socket_path)
      rescue
        # empty
      end

      @detached_agent_front = FrontObject.new

      # If the Unix domain socket is already in use and/or could not be removed
      # DRb will raise an appropriate error.
      @drb_server = DRb.start_service(detached_agent_socket_path, @detached_agent_front)

      # Only show DRb output in debug mode.
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
          raise Aikido::Zen::DetachedAgentError.new("Impossible to start the dRB server (socket=#{Aikido::Zen.config.detached_agent_socket_path})") \
            if attempts == max_attempts
        end

        @server
      end
    end
  end
end
