# frozen_string_literal: true

require "grpc"
require "google/protobuf/well_known_types"
require_relative "service_handler"

module Aikido::Zen
  module DetachedAgent
    class Server
      def initialize(collector:, config: Aikido::Zen.config)
        @config = config
        @server = ::GRPC::RpcServer.new
        @server.add_http2_port(config.detached_agent_socket_path, :this_port_is_insecure)
        @server.handle(Aikido::Zen::DetachedAgent::ServiceHandler.new(config: config, collector: collector))
      end

      def start!
        @server_thread = Thread.new do
          @config.logger.info "Start Zen::GRPC::DetachedAgent Server"
          @server.run_till_terminated_or_interrupted([1, "int", "SIGQUIT"])
        end
      end

      def stop!
        @server.stop
        @server_thread&.join
      end

      class << self
        def start!(collector)
          @server ||= Server.new(collector: collector)
          @server.start!
          @server
        end
      end
    end

    class Client
      def initialize(config: Aikido::Zen.config)
        @config = config
        socket_path = config.detached_agent_socket_path

        @client = Aikido::Zen::GRPC::DetachedAgent::Stub.new(socket_path, :this_channel_is_insecure, timeout: config.detached_agent_client_timeout)
      end

      def middleware_installed!
        @client.on_tracking(message(middleware_installed: Aikido::Zen::GRPC::MiddlewareInstalled.new(installed: true)))
      end

      def track_request(request)
        @client.on_tracking(message(request: Aikido::Zen::GRPC::Request.new))
      end

      private def message(**args)
        Aikido::Zen::GRPC::TrackInput.new(**args)
      end
    end
  end
end
