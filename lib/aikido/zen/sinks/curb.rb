# frozen_string_literal: true

require_relative "../scanners/stored_ssrf_scanner"
require_relative "../scanners/ssrf_scanner"

module Aikido::Zen
  module Sinks
    module Curl
      SINK = Sinks.add("curb", "outgoing_http_op", scanners: [
        Scanners::StoredSSRFScanner,
        Scanners::SSRFScanner
      ])

      module Helpers
        def self.wrap_request(curl, url: curl.url)
          Scanners::SSRFScanner::Request.new(
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

          Scanners::SSRFScanner::Response.new(status: status, headers: headers)
        end

        def self.resolve_hostname(hostname)
          require "resolv"
          Resolv.getaddresses(hostname)
        rescue => _error
          []
        end

        def self.scan(request, connection, operation, hostname: nil, addresses: nil)
          SINK.scan(
            request: request,
            connection: connection,
            operation: operation,
            hostname: hostname,
            addresses: addresses
          )
        end
      end

      def self.load_sinks!
        if Aikido::Zen.satisfy "curb", ">= 0.2.3"
          require "curb"

          ::Curl::Easy.class_eval do
            extend Sinks::DSL

            sink_around :perform do |original_call|
              wrapped_request = Helpers.wrap_request(self)

              # Store the request information so the DNS sinks can pick it up.
              context = Aikido::Zen.current_context
              if context
                prev_request = context["ssrf.request"]
                context["ssrf.request"] = wrapped_request
              end

              connection = OutboundConnection.from_uri(URI(url))

              unless Aikido::Zen.request_bypassed?
                Aikido::Zen.track_outbound(connection)

                if Aikido::Zen.block_outbound?(connection)
                  Sinks::DSL.presafe do
                    raise OutboundConnectionBlockedError.new(connection)
                  end
                end
              end

              # Resolve the hostname to get IP addresses for StoredSSRFScanner
              uri = URI(url)
              hostname = uri.hostname
              addresses = hostname ? Helpers.resolve_hostname(hostname) : []

              Helpers.scan(wrapped_request, connection, "request", hostname: hostname, addresses: addresses)

              response = original_call.call

              Scanners::SSRFScanner.track_redirects(
                request: wrapped_request,
                response: Helpers.wrap_response(self)
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
                last_effective_request = Helpers.wrap_request(self, url: last_effective_url)

                # Code coverage is disabled here because the else clause is a no-op,
                # so there is nothing to cover.
                # :nocov:
                if context
                  context["ssrf.request"] = last_effective_request
                else
                  # empty
                end
                # :nocov:

                connection = OutboundConnection.from_uri(URI(last_effective_url))

                # Resolve the redirect target hostname for StoredSSRFScanner
                redirect_uri = URI(last_effective_url)
                redirect_hostname = redirect_uri.hostname
                redirect_addresses = redirect_hostname ? Helpers.resolve_hostname(redirect_hostname) : []

                Helpers.scan(last_effective_request, connection, "request", hostname: redirect_hostname, addresses: redirect_addresses)
              end

              response
            ensure
              context["ssrf.request"] = prev_request if context
            end
          end
        end
      end
    end
  end
end

Aikido::Zen::Sinks::Curl.load_sinks!
