# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module Patron
      SINK = Sinks.add("patron", scanners: [
        Aikido::Zen::Scanners::SSRFScanner,
        Aikido::Zen::OutboundConnectionMonitor
      ])

      module Extensions
        def handle_request(request)
          wrapped_request = Aikido::Zen::HTTP::OutboundRequest.new(
            verb: request.action,
            uri: URI(request.url),
            headers: request.headers
          )

          SINK.scan(
            connection: Aikido::Zen::OutboundConnection.from_uri(URI(request.url)),
            request: wrapped_request,
            operation: "request"
          )

          response = super

          Aikido::Zen::Scanners::SSRFScanner.track_redirects(
            request: wrapped_request,
            response: Aikido::Zen::HTTP::OutboundResponse.new(
              status: response.status,
              headers: response.headers
            )
          )

          response
        end
      end
    end
  end
end

::Patron::Session.prepend(Aikido::Zen::Sinks::Patron::Extensions)
