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
          wrapped_request = Aikido::Zen::Scanners::SSRFScanner::Request.new(
            verb: request.action,
            uri: URI(request.url),
            headers: request.headers
          )

          # Store the request information so the DNS sinks can pick it up.
          if (context = Aikido::Zen.current_context)
            prev_request = context["ssrf.request"]
            context["ssrf.request"] = wrapped_request
          end

          SINK.scan(
            connection: Aikido::Zen::OutboundConnection.from_uri(URI(request.url)),
            request: wrapped_request,
            operation: "request"
          )

          response = super

          Aikido::Zen::Scanners::SSRFScanner.track_redirects(
            request: wrapped_request,
            response: Aikido::Zen::Scanners::SSRFScanner::Response.new(
              status: response.status,
              headers: response.headers
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

::Patron::Session.prepend(Aikido::Zen::Sinks::Patron::Extensions)
