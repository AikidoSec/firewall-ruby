# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Firewall
  module Sinks
    module Curl
      SINK = Sinks.add("curb", scanners: [
        Aikido::Firewall::OutboundConnectionMonitor
      ])

      module Extensions
        def perform
          conn = Aikido::Agent::OutboundConnection.from_uri(URI(url))
          SINK.scan(connection: conn, operation: "request")

          super
        end
      end
    end
  end
end

::Curl::Easy.prepend(Aikido::Firewall::Sinks::Curl::Extensions)
