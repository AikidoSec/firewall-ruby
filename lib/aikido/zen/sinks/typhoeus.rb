# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module Typhoeus
      SINK = Sinks.add("typhoeus", scanners: [
        Aikido::Zen::Scanners::SSRFScanner,
        Aikido::Zen::OutboundConnectionMonitor
      ])

      before_callback = ->(request) {
        wrapped_request = Aikido::Zen::Scanners::SSRFScanner::Request.new(
          verb: request.options[:method],
          uri: URI(request.url),
          headers: request.options[:headers]
        )

        # Store the request information so the DNS sinks can pick it up.
        if (context = Aikido::Zen.current_context)
          prev_request = context["ssrf.request"]
          context["ssrf.request"] = wrapped_request
        end

        SINK.scan(
          connection: Aikido::Zen::OutboundConnection.from_uri(URI(request.base_url)),
          request: wrapped_request,
          operation: "request"
        )

        request.on_headers do |response|
          context["ssrf.request"] = prev_request if context

          Aikido::Zen::Scanners::SSRFScanner.track_redirects(
            request: wrapped_request,
            response: Aikido::Zen::Scanners::SSRFScanner::Response.new(
              status: response.code,
              headers: response.headers.to_h
            )
          )
        end

        true
      }

      ::Typhoeus.before.prepend(before_callback)
    end
  end
end
