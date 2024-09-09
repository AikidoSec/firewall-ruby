# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module Curl
      SINK = Sinks.add("curb", scanners: [
        Aikido::Zen::OutboundConnectionMonitor
      ])

      module Extensions
        def perform
          conn = Aikido::Zen::OutboundConnection.from_uri(URI(url))
          SINK.scan(connection: conn, operation: "request")

          super
        end
      end
    end
  end
end

::Curl::Easy.prepend(Aikido::Zen::Sinks::Curl::Extensions)
