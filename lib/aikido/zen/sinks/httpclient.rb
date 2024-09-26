# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module HTTPClient
      SINK = Sinks.add("httpclient", scanners: [
        Aikido::Zen::Scanners::SSRFScanner,
        Aikido::Zen::OutboundConnectionMonitor
      ])

      module Extensions
        def self.wrap_request(req)
          Aikido::Zen::HTTP::OutboundRequest.new(
            verb: req.http_header.request_method,
            uri: req.http_header.request_uri,
            headers: req.headers
          )
        end

        def self.wrap_response(resp)
          Aikido::Zen::HTTP::OutboundResponse.new(
            status: resp.http_header.status_code,
            headers: resp.headers
          )
        end

        def do_get_block(req, *)
          SINK.scan(
            connection: Aikido::Zen::OutboundConnection.from_uri(req.http_header.request_uri),
            request: Extensions.wrap_request(req),
            operation: "request"
          )

          super
        end

        def do_get_stream(req, *)
          SINK.scan(
            connection: Aikido::Zen::OutboundConnection.from_uri(req.http_header.request_uri),
            request: Extensions.wrap_request(req),
            operation: "request"
          )

          super
        end

        def do_get_header(req, res, *)
          super.tap do
            Aikido::Zen::Scanners::SSRFScanner.track_redirects(
              request: Extensions.wrap_request(req),
              response: Extensions.wrap_response(res)
            )
          end
        end
      end
    end
  end
end

::HTTPClient.prepend(Aikido::Zen::Sinks::HTTPClient::Extensions)
