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

        class Middleware
          def response(client)
            Aikido::Zen::Scanners::SSRFScanner.track_redirects(
              request: Aikido::Zen::HTTP::OutboundRequest.new(
                verb: client.req.method,
                uri: URI(client.req.uri),
                headers: client.req.headers
              ),
              response: Aikido::Zen::HTTP::OutboundResponse.new(
                status: client.response_header.status,
                headers: client.response_header.to_h
              )
            )
          end
        end

        module Extensions
          def send_request(*)
            SINK.scan(
              connection: Aikido::Zen::OutboundConnection.new(
                host: req.host,
                port: req.port
              ),
              request: Aikido::Zen::HTTP::OutboundRequest.new(
                verb: req.method.to_s,
                uri: URI(req.uri),
                headers: req.headers
              ),
              operation: "request"
            )

            super
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
