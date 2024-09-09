# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module HTTP
      SINK = Sinks.add("http", scanners: [
        Aikido::Zen::OutboundConnectionMonitor
      ])

      module Extensions
        # Maps an HTTP Request to an Aikido OutboundConnection.
        #
        # @param http [HTTP::Request]
        # @return [Aikido::Zen::OutboundConnection]
        def self.build_outbound(req)
          Aikido::Zen::OutboundConnection.new(
            host: req.socket_host,
            port: req.socket_port
          )
        end

        def perform(req, *)
          conn = Extensions.build_outbound(req)
          SINK.scan(connection: conn, operation: "request")

          super
        end
      end
    end
  end
end

::HTTP::Client.prepend(Aikido::Zen::Sinks::HTTP::Extensions)
