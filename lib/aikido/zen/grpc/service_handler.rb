# frozen_string_literal: true

require_relative "lib/detached_agent_services_pb"

module Aikido::Zen
  module DetachedAgent
    class ServiceHandler < Aikido::Zen::GRPC::DetachedAgent::Service
      def initialize(
        config: Aikido::Zen.config,
        collector: Aikido::Zen::Collector.new(config: config)
      )
        @config = config
        @collector = collector
      end

      def on_tracking(message, kall)
        if message.middleware_installed&.installed
          @collector.middleware_installed!

        elsif message.request
          @collector.track_request(nil) # we don't actually care about this. Refactor later
        end

        Google::Protobuf::Empty.new
      rescue => e
        @config.logger.error(e.message)
        Google::Protobuf::Empty.new
      end

      # a new struct with the same shape that an Aikido::Zen::Request object
      Request = Struct.new(:route, :schema)
    end
  end
end
