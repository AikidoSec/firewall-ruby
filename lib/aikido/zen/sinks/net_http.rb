# frozen_string_literal: true

require_relative "../scanners/ssrf_scanner"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module Net
      module HTTP
        def self.load_sinks!
          ::Net::HTTP.prepend(Net::HTTP::HTTPExtensions)
        end

        SINK = Sinks.add("net-http", scanners: [
          Scanners::SSRFScanner,
          OutboundConnectionMonitor
        ])

        module Helpers
          # Maps a Net::HTTP connection to an Aikido OutboundConnection,
          # which our tooling expects.
          #
          # @param http [Net::HTTP]
          # @return [Aikido::Zen::OutboundConnection]
          def self.build_outbound(http)
            OutboundConnection.new(
              host: http.address,
              port: http.port
            )
          end

          def self.wrap_request(req, session)
            uri = req.uri if req.uri.is_a?(URI)
            uri ||= URI(format("%<scheme>s://%<hostname>s:%<port>s%<path>s", {
              scheme: session.use_ssl? ? "https" : "http",
              hostname: session.address,
              port: session.port,
              path: req.path
            }))

            Scanners::SSRFScanner::Request.new(
              verb: req.method,
              uri: uri,
              headers: req.to_hash,
              header_normalizer: ->(val) { Array(val).join(", ") }
            )
          end

          def self.wrap_response(response)
            Scanners::SSRFScanner::Response.new(
              status: response.code.to_i,
              headers: response.to_hash,
              header_normalizer: ->(val) { Array(val).join(", ") }
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

        module HTTPExtensions
          extend Sinks::DSL

          sink_around :request do |super_call, req|
            wrapped_request = Helpers.wrap_request(req, self)

            # Store the request information so the DNS sinks can pick it up.
            context = Aikido::Zen.current_context
            if context
              prev_request = context["ssrf.request"]
              context["ssrf.request"] = wrapped_request
            end

            connection = Helpers.build_outbound(self)

            Helpers.scan(wrapped_request, connection, "request")

            response = super_call.call

            Scanners::SSRFScanner.track_redirects(
              request: wrapped_request,
              response: Helpers.wrap_response(response)
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

Aikido::Zen::Sinks::Net::HTTP.load_sinks!
