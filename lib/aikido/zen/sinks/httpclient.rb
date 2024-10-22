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
          Aikido::Zen::Scanners::SSRFScanner::Request.new(
            verb: req.http_header.request_method,
            uri: req.http_header.request_uri,
            headers: req.headers
          )
        end

        def self.wrap_response(resp)
          Aikido::Zen::Scanners::SSRFScanner::Response.new(
            status: resp.http_header.status_code,
            headers: resp.headers
          )
        end

        def self.perform_scan(req, &block)
          wrapped_request = wrap_request(req)
          connection = Aikido::Zen::OutboundConnection.from_uri(req.http_header.request_uri)

          # Store the request information so the DNS sinks can pick it up.
          if (context = Aikido::Zen.current_context)
            prev_request = context["ssrf.request"]
            context["ssrf.request"] = wrapped_request
          end

          SINK.scan(connection: connection, request: wrapped_request, operation: "request")

          yield
        ensure
          context["ssrf.request"] = prev_request if context
        end

        def do_get_block(req, *)
          Extensions.perform_scan(req) { super }
        end

        def do_get_stream(req, *)
          Extensions.perform_scan(req) { super }
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
