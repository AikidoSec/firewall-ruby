# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module HTTPX
      SINK = Sinks.add("httpx", scanners: [
        Aikido::Zen::Scanners::SSRFScanner,
        Aikido::Zen::OutboundConnectionMonitor
      ])

      module Extensions
        def self.wrap_request(request)
          Aikido::Zen::Scanners::SSRFScanner::Request.new(
            verb: request.verb,
            uri: request.uri,
            headers: request.headers.to_hash
          )
        end

        def self.wrap_response(response)
          Aikido::Zen::Scanners::SSRFScanner::Response.new(
            status: response.status,
            headers: response.headers.to_hash
          )
        end

        def send_request(request, *)
          wrapped_request = Extensions.wrap_request(request)

          # Store the request information so the DNS sinks can pick it up.
          if (context = Aikido::Zen.current_context)
            prev_request = context["ssrf.request"]
            context["ssrf.request"] = wrapped_request
          end

          SINK.scan(
            connection: Aikido::Zen::OutboundConnection.from_uri(request.uri),
            request: wrapped_request,
            operation: "request"
          )

          request.on(:response) do |response|
            Aikido::Zen::Scanners::SSRFScanner.track_redirects(
              request: wrapped_request,
              response: Extensions.wrap_response(response)
            )
          end

          super
        ensure
          context["ssrf.request"] = prev_request if context
        end
      end
    end
  end
end

::HTTPX::Session.prepend(Aikido::Zen::Sinks::HTTPX::Extensions)
