# frozen_string_literal: true

require_relative "../sink"

module Aikido::Zen
  module Sinks
    module Typhoeus
      SINK = Sinks.add("typhoeus", "outgoing_http_op", scanners: [
        Aikido::Zen::Scanners::SSRFScanner
      ])

      module Helpers
        # Domain allowlist for SSRF protection against native libcurl requests.
        # libcurl performs DNS resolution in native code, bypassing Ruby's DNS
        # instrumentation, so we must validate domains before native execution.
        ALLOWED_DOMAINS = ['example.com'].freeze # add your allowed domains here

        def self.validate_url_domain(url_string)
          uri = URI(url_string)
          
          # Only allow http and https protocols
          unless uri.scheme == 'http' || uri.scheme == 'https'
            raise OutboundConnectionBlockedError.new(
              OutboundConnection.from_uri(uri),
              "Invalid URL"
            )
          end
          
          # Validate domain against allowlist
          hostname = uri.hostname
          unless hostname && ALLOWED_DOMAINS.include?(hostname)
            raise OutboundConnectionBlockedError.new(
              OutboundConnection.from_uri(uri),
              "Invalid URL"
            )
          end
          
          url_string
        rescue URI::InvalidURIError
          raise OutboundConnectionBlockedError.new(
            OutboundConnection.from_uri(URI(url_string)),
            "Invalid URL"
          )
        end
      end

      before_callback = ->(request) {
        # Validate URL domain before native libcurl execution
        Helpers.validate_url_domain(request.url)
        
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

        connection = Aikido::Zen::OutboundConnection.from_uri(URI(request.base_url))

        unless Aikido::Zen.request_bypassed?
          Aikido::Zen.track_outbound(connection)

          if Aikido::Zen.block_outbound?(connection)
            raise OutboundConnectionBlockedError.new(connection)
          end
        end

        SINK.scan(
          connection: connection,
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

          # Validate the redirect destination domain
          Helpers.validate_url_domain(response.effective_url)

          last_effective_request = Aikido::Zen::Scanners::SSRFScanner::Request.new(
            verb: request.options[:method],
            uri: URI(response.effective_url),
            headers: request.options[:headers]
          )
          context["ssrf.request"] = last_effective_request if context

          connection = Aikido::Zen::OutboundConnection.from_uri(URI(response.effective_url))

          # In this case, we can't actually stop the request from happening, but
          # we can scan again (now that we know another request happened), to
          # stop the response from being exposed to the user. This downgrades
          # the SSRF into a blind SSRF, which is better than doing nothing.
          SINK.scan(
            connection: connection,
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
