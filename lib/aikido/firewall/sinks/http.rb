# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Firewall
  module Sinks
    module HTTP
      SINK = Sinks.add("http", scanners: [
        Aikido::Firewall::OutboundConnectionMonitor
      ])

      # Maps an HTTP Request to an Aikido OutboundConnection.
      #
      # @param http [HTTP::Request]
      # @return [Aikido::Agent::OutboundConnection]
      def self.build_outbound(req)
        Aikido::Agent::OutboundConnection.new(
          host: req.socket_host,
          port: req.socket_port
        )
      end

      module Extensions
        def perform(req, *)
          conn = Aikido::Firewall::Sinks::HTTP.build_outbound(req)
          SINK.scan(connection: conn, operation: "request")

          super
        end
      end
    end
  end
end

::HTTP::Client.prepend(Aikido::Firewall::Sinks::HTTP::Extensions)
