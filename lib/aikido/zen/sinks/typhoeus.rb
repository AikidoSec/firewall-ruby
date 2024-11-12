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

        # When Typhoeus is configured with followlocation: true, the redirect
        # following happens between the on_headers and the on_complete callback,
        # so we need this one to detect if the request resulted in an automatic
        # redirect that was followed.
        request.on_complete do |response|
          break if response.effective_url == request.url

          last_effective_request = Aikido::Zen::Scanners::SSRFScanner::Request.new(
            verb: request.options[:method],
            uri: URI(response.effective_url),
            headers: request.options[:headers]
          )
          context["ssrf.request"] = last_effective_request if context

          # In this case, we can't actually stop the request from happening, but
          # we can scan again (now that we know another request happened), to
          # stop the response from being exposed to the user. This downgrades
          # the SSRF into a blind SSRF, which is better than doing nothing.
          SINK.scan(
            connection: Aikido::Zen::OutboundConnection.from_uri(URI(response.effective_url)),
            request: last_effective_request,
            operation: "request"
          )
        ensure
          context["ssrf.request"] = nil if context
        end

        true
      }

      ::Typhoeus.before.prepend(before_callback)
    end
  end
end
