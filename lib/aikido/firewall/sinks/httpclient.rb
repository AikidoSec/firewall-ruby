# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Firewall
  module Sinks
    module HTTPClient
      SINK = Sinks.add("httpclient", scanners: [
        Aikido::Firewall::OutboundConnectionMonitor
      ])

      module Extensions
        def do_get_block(req, *)
          conn = Aikido::Agent::OutboundConnection.from_uri(req.http_header.request_uri)
          SINK.scan(connection: conn, operation: "request")

          super
        end

        def do_get_stream(req, *)
          conn = Aikido::Agent::OutboundConnection.from_uri(req.http_header.request_uri)
          SINK.scan(connection: conn, operation: "request")

          super
        end
      end
    end
  end
end

::HTTPClient.prepend(Aikido::Firewall::Sinks::HTTPClient::Extensions)
