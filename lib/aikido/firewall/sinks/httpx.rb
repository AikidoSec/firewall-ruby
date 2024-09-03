# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Firewall
  module Sinks
    module HTTPX
      SINK = Sinks.add("httpx", scanners: [
        Aikido::Firewall::OutboundConnectionMonitor
      ])

      # Maps an HTTPX Request to an Aikido OutboundConnection.
      #
      # @param request [HTTPX::Request]
      # @return [Aikido::Agent::OutboundConnection]
      def self.build_outbound(request)
        Aikido::Agent::OutboundConnection.new(
          host: request.uri.hostname,
          port: request.uri.port
        )
      end

      module Extensions
        def send_request(request, *)
          conn = Aikido::Firewall::Sinks::HTTPX.build_outbound(request)
          SINK.scan(connection: conn, operation: "request")

          super
        end
      end
    end
  end
end

::HTTPX::Session.prepend(Aikido::Firewall::Sinks::HTTPX::Extensions)
