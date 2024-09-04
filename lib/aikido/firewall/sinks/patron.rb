# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Firewall
  module Sinks
    module Patron
      SINK = Sinks.add("patron", scanners: [
        Aikido::Firewall::OutboundConnectionMonitor
      ])

      module Extensions
        def handle_request(request)
          conn = Aikido::Agent::OutboundConnection.from_uri(URI(request.url))
          SINK.scan(connection: conn, operation: "request")

          super
        end
      end
    end
  end
end

::Patron::Session.prepend(Aikido::Firewall::Sinks::Patron::Extensions)
