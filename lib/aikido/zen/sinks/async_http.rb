# frozen_string_literal: true

require_relative "../scanners/ssrf_scanner"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module Async
      module HTTP
        SINK = Sinks.add("async-http", scanners: [
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

        def self.load_sinks!
          if Aikido::Zen.satisfy "async-http", ">= 0.70.0"
            require "async/http"

            ::Async::HTTP::Client.class_eval do
              extend Sinks::DSL

              sink_around :call do |original_call, request|
                uri = URI(format("%<scheme>s://%<authority>s%<path>s", {
                  scheme: request.scheme || scheme,
                  authority: request.authority || authority,
                  path: request.path
                }))

                wrapped_request = Scanners::SSRFScanner::Request.new(
                  verb: request.method,
                  uri: uri,
                  headers: request.headers.to_h,
                  header_normalizer: ->(value) { Array(value).join(", ") }
                )

                # Store the request information so the DNS sinks can pick it up.
                context = Aikido::Zen.current_context
                if context
                  prev_request = context["ssrf.request"]
                  context["ssrf.request"] = wrapped_request
                end

                connection = OutboundConnection.from_uri(uri)

                Helpers.scan(wrapped_request, connection, "request")

                response = original_call.call

                Scanners::SSRFScanner.track_redirects(
                  request: wrapped_request,
                  response: Scanners::SSRFScanner::Response.new(
                    status: response.status,
                    headers: response.headers.to_h,
                    header_normalizer: ->(value) { Array(value).join(", ") }
                  )
                )

                response
              ensure
                context["ssrf.request"] = prev_request if context
              end
            end
          end
        end
      end
    end
  end
end

Aikido::Zen::Sinks::Async::HTTP.load_sinks!
