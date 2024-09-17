# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module Net
      module HTTP
        SINK = Sinks.add("net-http", scanners: [
          Aikido::Zen::OutboundConnectionMonitor
        ])

        module Extensions
          # Maps a Net::HTTP connection to an Aikido OutboundConnection,
          # which our tooling expects.
          #
          # @param http [Net::HTTP]
          # @return [Aikido::Zen::OutboundConnection]
          def self.build_outbound(http)
            Aikido::Zen::OutboundConnection.new(
              host: http.address,
              port: http.port
            )
          end

          def request(req, *)
            conn = Extensions.build_outbound(self)
            SINK.scan(connection: conn, operation: "request")

            super
          end
        end
      end
    end
  end
end

::Net::HTTP.prepend(Aikido::Zen::Sinks::Net::HTTP::Extensions)
