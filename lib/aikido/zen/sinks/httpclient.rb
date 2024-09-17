# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module HTTPClient
      SINK = Sinks.add("httpclient", scanners: [
        Aikido::Zen::OutboundConnectionMonitor
      ])

      module Extensions
        def do_get_block(req, *)
          conn = Aikido::Zen::OutboundConnection.from_uri(req.http_header.request_uri)
          SINK.scan(connection: conn, operation: "request")

          super
        end

        def do_get_stream(req, *)
          conn = Aikido::Zen::OutboundConnection.from_uri(req.http_header.request_uri)
          SINK.scan(connection: conn, operation: "request")

          super
        end
      end
    end
  end
end

::HTTPClient.prepend(Aikido::Zen::Sinks::HTTPClient::Extensions)
