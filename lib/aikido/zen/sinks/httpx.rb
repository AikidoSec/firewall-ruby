# frozen_string_literal: true

require_relative "../scanners/ssrf_scanner"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module HTTPX
      SINK = Sinks.add("httpx", scanners: [
        Scanners::SSRFScanner,
        OutboundConnectionMonitor
      ])

      module Helpers
        def self.wrap_request(request)
          Scanners::SSRFScanner::Request.new(
            verb: request.verb,
            uri: request.uri,
            headers: request.headers.to_hash
          )
        end

        def self.wrap_response(response)
          Scanners::SSRFScanner::Response.new(
            status: response.status,
            headers: response.headers.to_hash
          )
        end

        def self.scan(request, connection, operation)
          SINK.scan(
            request: request,
            connection: connection,
            operation: operation
          )
        end
      end

      def self.load_sinks!
        if Aikido::Zen.satisfy "httpx", ">= 1.1.3"
          require "httpx"

          ::HTTPX::Session.class_eval do
            extend Sinks::DSL

            sink_around :send_request do |original_call, request|
              wrapped_request = Helpers.wrap_request(request)

              # Store the request information so the DNS sinks can pick it up.
              context = Aikido::Zen.current_context
              if context
                prev_request = context["ssrf.request"]
                context["ssrf.request"] = wrapped_request
              end

              connection = OutboundConnection.from_uri(request.uri)

              Helpers.scan(wrapped_request, connection, "request")

              request.on(:response) do |response|
                Scanners::SSRFScanner.track_redirects(
                  request: wrapped_request,
                  response: Helpers.wrap_response(response)
                )
              end

              original_call.call
            ensure
              context["ssrf.request"] = prev_request if context
            end
          end
        end
      end
    end
  end
end

Aikido::Zen::Sinks::HTTPX.load_sinks!
