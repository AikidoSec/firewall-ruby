# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module Patron
      SINK = Sinks.add("patron", scanners: [
        Aikido::Zen::OutboundConnectionMonitor
      ])

      module Extensions
        def handle_request(request)
          conn = Aikido::Zen::OutboundConnection.from_uri(URI(request.url))
          SINK.scan(connection: conn, operation: "request")

          super
        end
      end
    end
  end
end

::Patron::Session.prepend(Aikido::Zen::Sinks::Patron::Extensions)
