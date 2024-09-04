# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Firewall
  module Sinks
    module Async
      module HTTP
        SINK = Sinks.add("async-http", scanners: [
          Aikido::Firewall::OutboundConnectionMonitor
        ])

        # Maps an Async::HTTP request to an Aikido OutboundConnection.
        #
        # @param request [Async::HTTP::Protocol::Request]
        # @return [Aikido::Agent::OutboundConnection]
        def self.build_outbound(request)
          uri = URI(format("%s://%s", request.scheme, request.authority))
          Aikido::Agent::OutboundConnection.from_uri(uri)
        end

        module Extensions
          def call(request)
            conn = Aikido::Firewall::Sinks::Async::HTTP.build_outbound(request)
            SINK.scan(connection: conn, operation: "request")

            super
          end
        end
      end
    end
  end
end

::Async::HTTP::Client.prepend(Aikido::Firewall::Sinks::Async::HTTP::Extensions)
