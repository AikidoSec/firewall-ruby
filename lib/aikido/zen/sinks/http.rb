# frozen_string_literal: true

require_relative "../scanners/ssrf_scanner"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module HTTP
      def self.load_sinks!
        if Gem.loaded_specs["http"]
          require "http"

          ::HTTP::Client.prepend(ClientExtensions)
        end
      end

      SINK = Sinks.add("http", scanners: [
        Scanners::SSRFScanner,
        OutboundConnectionMonitor
      ])

      module Helpers
        # Maps an HTTP Request to an Aikido OutboundConnection.
        #
        # @param req [HTTP::Request]
        # @return [Aikido::Zen::OutboundConnection]
        def self.build_outbound(req)
          OutboundConnection.new(
            host: req.socket_host,
            port: req.socket_port
          )
        end

        # Wraps the HTTP request with an API we can depend on.
        #
        # @param req [HTTP::Request]
        # @return [Aikido::Zen::Scanners::SSRFScanner::Request]
        def self.wrap_request(req)
          Scanners::SSRFScanner::Request.new(
            verb: req.verb,
            uri: URI(req.uri.to_s),
            headers: req.headers.to_h
          )
        end

        def self.wrap_response(resp)
          Scanners::SSRFScanner::Response.new(
            status: resp.status,
            headers: resp.headers.to_h
          )
        end

        def self.scan(request, connection, operation)
          SINK.scan(
            request: request,
            connection: connection,
            operation: operation
          )
        end
      end

      module ClientExtensions
        extend Sinks::DSL

        sink_around :perform do |super_call, req|
          wrapped_request = Helpers.wrap_request(req)

          # Store the request information so the DNS sinks can pick it up.
          context = Aikido::Zen.current_context
          if context
            prev_request = context["ssrf.request"]
            context["ssrf.request"] = wrapped_request
          end

          connection = Helpers.build_outbound(req)

          Helpers.scan(wrapped_request, connection, "request")

          response = super_call.call

          Scanners::SSRFScanner.track_redirects(
            request: wrapped_request,
            response: Helpers.wrap_response(response)
          )

          response
        ensure
          context["ssrf.request"] = prev_request if context
        end
      end
    end
  end
end

Aikido::Zen::Sinks::HTTP.load_sinks!
