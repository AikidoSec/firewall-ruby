# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Firewall
  module Sinks
    module Net
      module HTTP
        SINK = Sinks.add("net-http", scanners: [
          Aikido::Firewall::OutboundConnectionMonitor
        ])

        # Maps a Net::HTTP connection to an Aikido OutboundConnection,
        # which our tooling expects.
        #
        # @param http [Net::HTTP]
        # @return [Aikido::Agent::OutboundConnection]
        def self.build_outbound(http)
          Aikido::Agent::OutboundConnection.new(
            host: http.address,
            port: http.port
          )
        end

        module Extensions
          def request(req, *)
            conn = Aikido::Firewall::Sinks::Net::HTTP.build_outbound(self)
            SINK.scan(connection: conn, operation: "request")

            super
          end
        end
      end
    end
  end
end

::Net::HTTP.prepend(Aikido::Firewall::Sinks::Net::HTTP::Extensions)
