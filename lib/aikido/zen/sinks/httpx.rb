# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module HTTPX
      SINK = Sinks.add("httpx", scanners: [
        Aikido::Zen::OutboundConnectionMonitor
      ])

      module Extensions
        def send_request(request, *)
          conn = Aikido::Zen::OutboundConnection.from_uri(request.uri)
          SINK.scan(connection: conn, operation: "request")

          super
        end
      end
    end
  end
end

::HTTPX::Session.prepend(Aikido::Zen::Sinks::HTTPX::Extensions)
