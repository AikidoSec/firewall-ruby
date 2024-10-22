# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module EventMachine
      module HttpRequest
        SINK = Sinks.add("em-http-request", scanners: [
          Aikido::Zen::Scanners::SSRFScanner,
          Aikido::Zen::OutboundConnectionMonitor
        ])

        module Extensions
          def send_request(*)
            wrapped_request = Aikido::Zen::Scanners::SSRFScanner::Request.new(
              verb: req.method.to_s,
              uri: URI(req.uri),
              headers: req.headers
            )

            # Store the request information so the DNS sinks can pick it up.
            context = Aikido::Zen.current_context
            context["ssrf.request"] = wrapped_request if context

            SINK.scan(
              connection: Aikido::Zen::OutboundConnection.new(
                host: req.host,
                port: req.port
              ),
              request: wrapped_request,
              operation: "request"
            )

            super
          end
        end

        class Middleware
          def response(client)
            # Store the request information so the DNS sinks can pick it up.
            context = Aikido::Zen.current_context
            context["ssrf.request"] = nil if context

            Aikido::Zen::Scanners::SSRFScanner.track_redirects(
              request: Aikido::Zen::Scanners::SSRFScanner::Request.new(
                verb: client.req.method,
                uri: URI(client.req.uri),
                headers: client.req.headers
              ),
              response: Aikido::Zen::Scanners::SSRFScanner::Response.new(
                status: client.response_header.status,
                headers: client.response_header.to_h
              )
            )
          end
        end
      end
    end
  end
end

::EventMachine::HttpRequest
  .use(Aikido::Zen::Sinks::EventMachine::HttpRequest::Middleware)

# NOTE: We can't use middleware to intercept requests as we want to ensure any
# modifications to the request from user-supplied middleware are already applied
# before we scan the request.
::EventMachine::HttpClient
  .prepend(Aikido::Zen::Sinks::EventMachine::HttpRequest::Extensions)
