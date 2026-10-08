# frozen_string_literal: true

require_relative "../scanners/stored_ssrf_scanner"
require_relative "../scanners/ssrf_scanner"

module Aikido::Zen
  module Sinks
    module Patron
      SINK = Sinks.add("patron", "outgoing_http_op", scanners: [
        Scanners::StoredSSRFScanner,
        Scanners::SSRFScanner
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
        if Aikido::Zen.satisfy "patron", ">= 0.6.4"
          require "patron"

          ::Patron::Session.class_eval do
            extend Sinks::DSL

            sink_around :handle_request do |original_call, request|
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

              unless Aikido::Zen.request_bypassed?
                Aikido::Zen.track_outbound(connection)

                if Aikido::Zen.block_outbound?(connection)
                  Sinks::DSL.presafe do
                    raise OutboundConnectionBlockedError.new(connection)
                  end
                end
              end

              # Resolve the hostname to get IP addresses for StoredSSRFScanner
              uri = URI(request.url)
              hostname = uri.hostname
              addresses = hostname ? Helpers.resolve_hostname(hostname) : []

              Helpers.scan(wrapped_request, connection, "request", hostname: hostname, addresses: addresses)

              response = original_call.call

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

                # Resolve the redirect target hostname for StoredSSRFScanner
                redirect_uri = URI(response.url)
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

Aikido::Zen::Sinks::Patron.load_sinks!
