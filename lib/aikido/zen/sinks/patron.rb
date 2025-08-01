# frozen_string_literal: true

require_relative "../scanners/ssrf_scanner"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module Patron
      def self.load_sinks!
        if Aikido::Zen.satisfy "patron", ">= 0.6.4"
          require "patron"

          ::Patron::Session.prepend(SessionExtensions)
        end
      end

      SINK = Sinks.add("patron", scanners: [
        Scanners::SSRFScanner,
        OutboundConnectionMonitor
      ])

      module Helpers
        def self.wrap_response(request, response)
          # In this case, automatic redirection happened inside libcurl.
          if response.url != request.url && !response.url.to_s.empty?
            Scanners::SSRFScanner::Response.new(
              status: 302, # We can't know what the actual status was, but we just need a 3XX
              headers: response.headers.merge("Location" => response.url)
            )
          else
            Scanners::SSRFScanner::Response.new(
              status: response.status,
              headers: response.headers
            )
          end
        end

        def self.scan(request, connection, operation)
          SINK.scan(
            request: request,
            connection: connection,
            operation: operation
          )
        end
      end

      module SessionExtensions
        extend Sinks::DSL

        sink_around :handle_request do |super_call, request|
          wrapped_request = Scanners::SSRFScanner::Request.new(
            verb: request.action,
            uri: URI(request.url),
            headers: request.headers
          )

          # Store the request information so the DNS sinks can pick it up.
          context = Aikido::Zen.current_context
          if context
            prev_request = context["ssrf.request"]
            context["ssrf.request"] = wrapped_request
          end

          connection = OutboundConnection.from_uri(URI(request.url))

          Helpers.scan(wrapped_request, connection, "request")

          response = super_call.call

          Scanners::SSRFScanner.track_redirects(
            request: wrapped_request,
            response: Helpers.wrap_response(request, response)
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
            last_effective_request = Scanners::SSRFScanner::Request.new(
              verb: request.action,
              uri: URI(response.url),
              headers: request.headers
            )
            context["ssrf.request"] = last_effective_request if context

            connection = OutboundConnection.from_uri(URI(response.url))

            Helpers.scan(last_effective_request, connection, "request")
          end

          response
        ensure
          context["ssrf.request"] = prev_request if context
        end
      end
    end
  end
end

Aikido::Zen::Sinks::Patron.load_sinks!
