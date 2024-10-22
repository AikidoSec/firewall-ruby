# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module Net
      module HTTP
        SINK = Sinks.add("net-http", scanners: [
          Aikido::Zen::Scanners::SSRFScanner,
          Aikido::Zen::OutboundConnectionMonitor
        ])

        module Extensions
          # Maps a Net::HTTP connection to an Aikido OutboundConnection,
          # which our tooling expects.
          #
          # @param http [Net::HTTP]
          # @return [Aikido::Zen::OutboundConnection]
          def self.build_outbound(http)
            Aikido::Zen::OutboundConnection.new(
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

            Aikido::Zen::Scanners::SSRFScanner::Request.new(
              verb: req.method,
              uri: uri,
              headers: req.to_hash,
              header_normalizer: ->(val) { Array(val).join(", ") }
            )
          end

          def self.wrap_response(response)
            Aikido::Zen::Scanners::SSRFScanner::Response.new(
              status: response.code.to_i,
              headers: response.to_hash,
              header_normalizer: ->(val) { Array(val).join(", ") }
            )
          end

          def request(req, *)
            wrapped_request = Extensions.wrap_request(req, self)

            # Store the request information so the DNS sinks can pick it up.
            if (context = Aikido::Zen.current_context)
              prev_request = context["ssrf.request"]
              context["ssrf.request"] = wrapped_request
            end

            SINK.scan(
              connection: Extensions.build_outbound(self),
              request: wrapped_request,
              operation: "request"
            )

            response = super

            Aikido::Zen::Scanners::SSRFScanner.track_redirects(
              request: wrapped_request,
              response: Extensions.wrap_response(response)
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

::Net::HTTP.prepend(Aikido::Zen::Sinks::Net::HTTP::Extensions)
