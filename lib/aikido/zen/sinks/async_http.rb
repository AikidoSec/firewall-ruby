# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module Async
      module HTTP
        SINK = Sinks.add("async-http", scanners: [
          Aikido::Zen::Scanners::SSRFScanner,
          Aikido::Zen::OutboundConnectionMonitor
        ])

        module Extensions
          def call(request)
            uri = URI(format("%<scheme>s://%<authority>s%<path>s", {
              scheme: request.scheme || scheme,
              authority: request.authority || authority,
              path: request.path
            }))

            wrapped_request = Aikido::Zen::Scanners::SSRFScanner::Request.new(
              verb: request.method,
              uri: uri,
              headers: request.headers.to_h,
              header_normalizer: ->(value) { Array(value).join(", ") }
            )

            SINK.scan(
              connection: Aikido::Zen::OutboundConnection.from_uri(uri),
              request: wrapped_request,
              operation: "request"
            )

            response = super

            Aikido::Zen::Scanners::SSRFScanner.track_redirects(
              request: wrapped_request,
              response: Aikido::Zen::Scanners::SSRFScanner::Response.new(
                status: response.status,
                headers: response.headers.to_h,
                header_normalizer: ->(value) { Array(value).join(", ") }
              )
            )

            response
          end
        end
      end
    end
  end
end

::Async::HTTP::Client.prepend(Aikido::Zen::Sinks::Async::HTTP::Extensions)
