# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module Async
      module HTTP
        SINK = Sinks.add("async-http", scanners: [
          Aikido::Zen::OutboundConnectionMonitor
        ])

        module Extensions
          # Maps an Async::HTTP request to an Aikido OutboundConnection.
          #
          # @param request [Async::HTTP::Protocol::Request]
          # @return [Aikido::Zen::OutboundConnection]
          def self.build_outbound(request)
            uri = URI(format("%s://%s", request.scheme, request.authority))
            Aikido::Zen::OutboundConnection.from_uri(uri)
          end

          def call(request)
            conn = Extensions.build_outbound(request)
            SINK.scan(connection: conn, operation: "request")

            super
          end
        end
      end
    end
  end
end

::Async::HTTP::Client.prepend(Aikido::Zen::Sinks::Async::HTTP::Extensions)
