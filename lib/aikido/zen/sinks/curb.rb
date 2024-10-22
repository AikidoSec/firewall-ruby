# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module Curl
      SINK = Sinks.add("curb", scanners: [
        Aikido::Zen::Scanners::SSRFScanner,
        Aikido::Zen::OutboundConnectionMonitor
      ])

      module Extensions
        def self.wrap_request(curl, url: curl.url)
          Aikido::Zen::Scanners::SSRFScanner::Request.new(
            verb: nil, # Curb hides this by directly setting an option in C
            uri: URI(url),
            headers: curl.headers
          )
        end

        def self.wrap_response(curl)
          # Curb made an… interesting choice by not parsing the response headers
          # and forcing users to do this manually if they need to look at them.
          _, *headers = curl.header_str.split(/[\r\n]+/).map(&:strip)
          headers = headers.flat_map { |str| str.scan(/\A(\S+): (.+)\z/) }.to_h

          if curl.url != curl.last_effective_url
            status = 302 # We can't know what the original status was, but we just need a 3XX
            headers["Location"] = curl.last_effective_url
          else
            status = curl.status.to_i
          end

          Aikido::Zen::Scanners::SSRFScanner::Response.new(status: status, headers: headers)
        end

        def perform
          wrapped_request = Extensions.wrap_request(self)

          # Store the request information so the DNS sinks can pick it up.
          if (context = Aikido::Zen.current_context)
            prev_request = context["ssrf.request"]
            context["ssrf.request"] = wrapped_request
          end

          SINK.scan(
            connection: Aikido::Zen::OutboundConnection.from_uri(URI(url)),
            request: wrapped_request,
            operation: "request"
          )

          response = super

          Aikido::Zen::Scanners::SSRFScanner.track_redirects(
            request: wrapped_request,
            response: Extensions.wrap_response(self)
          )

          # When libcurl has follow_location set, it will handle redirections
          # internally, and expose the "last_effective_url" as the URI that was
          # last requested in the redirect chain.
          #
          # In this case, we can't actually stop the request from happening, but
          # we can scan again (now that we know another request happened), to
          # stop the response from being exposed to the user. This downgrades
          # the SSRF into a blind SSRF, which is better than doing nothing.
          if url != last_effective_url
            last_effective_request = Extensions.wrap_request(self, url: last_effective_url)
            context["ssrf.request"] = last_effective_request if context

            SINK.scan(
              connection: Aikido::Zen::OutboundConnection.from_uri(URI(last_effective_url)),
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

::Curl::Easy.prepend(Aikido::Zen::Sinks::Curl::Extensions)
