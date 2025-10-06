# frozen_string_literal: true

require "fileutils"

module Aikido::Zen::IPC
  class Server
    # Initialize and start IPC server instance.
    #
    # @return [Aikido::Zen::IPC::Server]
    def self.start(**opts)
      new(**opts).tap(&:start!)
    end

    def initialize(config: Aikido::Zen.config)
      @started_at = nil

      @config = config
      @socket_path = config.ipc_server_socket_path
      @socket_uri = config.ipc_server_socket_uri
    end

    def started?
      !!@started_at
    end

    def start!
      @config.logger.info("Starting DRb Server...")

      # Try to ensure that the DRb service can start if the DRb service did
      # not stop cleanly.
      begin
        # Check whether the Unix domain socket is in use by another process.
        UNIXSocket.new(@socket_path).close
      rescue Errno::ECONNREFUSED
        @config.logger.debug("Removing residual Unix domain socket...")

        # Remove the residual Unix domain socket.
        FileUtils.rm_f(@socket_path)
      rescue
        # empty
      end

      @front_object = FrontObject.new

      # If the Unix domain socket is in use by another process and/or the
      # residual Unix domain socket could not be removed DRb will raise an
      # appropriate error.
      @drb_server = DRb.start_service(@socket_uri, @front_object)

      # Only show DRb output in debug mode.
      @drb_server.verbose = @config.logger.debug?

      # Ensure that the DRb server is alive.
      max_attempts = 10
      attempts = 0
      until @drb_server.alive?
        @config.logger.info("DRb Server still not alive. #{max_attempts - attempts} attempts remaining")
        sleep 0.1
        attempts += 1
        raise Aikido::Zen::IPCError.new("Impossible to start the dRB server (socket=#{Aikido::Zen.config.ipc_server_socket_path})") \
          if attempts == max_attempts
      end

      @started_at = Time.now.utc

      at_exit { stop! if started? }
    end

    def stop!
      @config.logger.info("Stopping DRb Server...")
      @started_at = nil

      @drb_server.stop_service if @drb_server.alive?
      DRb.stop_service
    end
  end
end
