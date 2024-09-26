# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module HTTP
      SINK = Sinks.add("http", scanners: [
        Aikido::Zen::Scanners::SSRFScanner,
        Aikido::Zen::OutboundConnectionMonitor
      ])

      module Extensions
        # Maps an HTTP Request to an Aikido OutboundConnection.
        #
        # @param req [HTTP::Request]
        # @return [Aikido::Zen::OutboundConnection]
        def self.build_outbound(req)
          Aikido::Zen::OutboundConnection.new(
            host: req.socket_host,
            port: req.socket_port
          )
        end

        # Wraps the HTTP request with an API we can depend on.
        #
        # @param req [HTTP::Request]
        # @return [Aikido::Zen::HTTP::OutboundRequest]
        def self.wrap_request(req)
          Aikido::Zen::HTTP::OutboundRequest.new(
            verb: req.verb,
            uri: URI(req.uri.to_s),
            headers: req.headers.to_h
          )
        end

        def self.wrap_response(resp)
          Aikido::Zen::HTTP::OutboundResponse.new(
            status: resp.status,
            headers: resp.headers.to_h
          )
        end

        def perform(req, *)
          wrapped_request = Extensions.wrap_request(req)

          SINK.scan(
            request: wrapped_request,
            connection: Extensions.build_outbound(req),
            operation: "request"
          )

          response = super

          Aikido::Zen::Scanners::SSRFScanner.track_redirects(
            request: wrapped_request,
            response: Extensions.wrap_response(response)
          )

          response
        end
      end
    end
  end
end

::HTTP::Client.prepend(Aikido::Zen::Sinks::HTTP::Extensions)
