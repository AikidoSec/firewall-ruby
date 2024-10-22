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
        def self.wrap_response(request, response)
          # In this case, automatic redirection happened inside libcurl.
          if response.url != request.url && !response.url.to_s.empty?
            Aikido::Zen::Scanners::SSRFScanner::Response.new(
              status: 302, # We can't know what the actual status was, but we just need a 3XX
              headers: response.headers.merge("Location" => response.url)
            )
          else
            Aikido::Zen::Scanners::SSRFScanner::Response.new(
              status: response.status,
              headers: response.headers
            )
          end
        end

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
            response: Extensions.wrap_response(request, response)
          )

          # When libcurl has follow_location set, it will handle redirections
          # internally, and expose the response.url as the URI that was last
          # requested in the redirect chain.
          #
          # In this case, we can't actually stop the request from happening, but
          # we can scan again (now that we know another request happened), to
          # stop the response from being exposed to the user. This downgrades
          # the SSRF into a blind SSRF, which is better than doing nothing.
          if request.url != response.url && !response.url.to_s.empty?
            last_effective_request = Aikido::Zen::Scanners::SSRFScanner::Request.new(
              verb: request.action,
              uri: URI(response.url),
              headers: request.headers
            )
            context["ssrf.request"] = last_effective_request if context

            SINK.scan(
              connection: Aikido::Zen::OutboundConnection.from_uri(URI(response.url)),
              request: last_effective_request,
              operation: "request"
            )
          end

          response
        ensure
          context["ssrf.request"] = prev_request if context
        end
      end
    end
  end
end

::Patron::Session.prepend(Aikido::Zen::Sinks::Patron::Extensions)
