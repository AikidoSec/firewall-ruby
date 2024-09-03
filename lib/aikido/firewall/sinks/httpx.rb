# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Firewall
  module Sinks
    module HTTPX
      SINK = Sinks.add("httpx", scanners: [
        Aikido::Firewall::OutboundConnectionMonitor
      ])

      module Extensions
        def send_request(request, *)
          conn = Aikido::Agent::OutboundConnection.from_uri(request.uri)
          SINK.scan(connection: conn, operation: "request")

          super
        end
      end
    end
  end
end

::HTTPX::Session.prepend(Aikido::Firewall::Sinks::HTTPX::Extensions)
