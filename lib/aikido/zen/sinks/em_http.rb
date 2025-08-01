# frozen_string_literal: true

require_relative "../scanners/ssrf_scanner"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module EventMachine
      module HttpRequest
        def self.load_sinks!
          if Aikido::Zen.satisfy "em-http-request", ">= 1.0"
            require "em-http-request"

            ::EventMachine::HttpRequest.use(EventMachine::HttpRequest::Middleware)

            # NOTE: We can't use middleware to intercept requests as we want to ensure any
            # modifications to the request from user-supplied middleware are already applied
            # before we scan the request.
            ::EventMachine::HttpClient.prepend(EventMachine::HttpRequest::HttpClientExtensions)
          end
        end

        SINK = Sinks.add("em-http-request", scanners: [
          Scanners::SSRFScanner,
          OutboundConnectionMonitor
        ])

        module Helpers
          def self.scan(request, connection, operation)
            SINK.scan(
              request: request,
              connection: connection,
              operation: operation
            )
          end
        end

        module HttpClientExtensions
          extend Sinks::DSL

          sink_before :send_request do
            wrapped_request = Scanners::SSRFScanner::Request.new(
              verb: req.method.to_s,
              uri: URI(req.uri),
              headers: req.headers
            )

            # Store the request information so the DNS sinks can pick it up.
            context = Aikido::Zen.current_context
            context["ssrf.request"] = wrapped_request if context

            connection = OutboundConnection.new(
              host: req.host,
              port: req.port
            )

            Helpers.scan(wrapped_request, connection, "request")
          end
        end

        class Middleware
          def response(client)
            # Store the request information so the DNS sinks can pick it up.
            context = Aikido::Zen.current_context
            context["ssrf.request"] = nil if context

            Scanners::SSRFScanner.track_redirects(
              request: Scanners::SSRFScanner::Request.new(
                verb: client.req.method,
                uri: URI(client.req.uri),
                headers: client.req.headers
              ),
              response: Scanners::SSRFScanner::Response.new(
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

Aikido::Zen::Sinks::EventMachine::HttpRequest.load_sinks!
