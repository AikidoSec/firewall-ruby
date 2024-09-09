# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module Typhoeus
      SINK = Sinks.add("typhoeus", scanners: [
        Aikido::Zen::OutboundConnectionMonitor
      ])

      before_callback = ->(request) {
        conn = Aikido::Zen::OutboundConnection.from_uri(URI(request.base_url))
        SINK.scan(connection: conn, operation: "request")

        true
      }

      ::Typhoeus.before.prepend(before_callback)
    end
  end
end
