# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module Excon
      SINK = Sinks.add("excon", scanners: [
        Aikido::Zen::Scanners::SSRFScanner,
        Aikido::Zen::OutboundConnectionMonitor
      ])

      module Extensions
        # Maps Excon request params to an Aikido OutboundConnection.
        #
        # @param connection [Hash<Symbol, Object>] the data set in the connection.
        # @param request [Hash<Symbol, Object>] the data overrides sent for each
        #   request.
        #
        # @return [Aikido::Zen::OutboundConnection]
        def self.build_outbound(connection, request)
          Aikido::Zen::OutboundConnection.new(
            host: request.fetch(:hostname) { connection[:hostname] },
            port: request.fetch(:port) { connection[:port] }
          )
        end

        def self.build_request(connection, request)
          uri = URI(format("%<scheme>s://%<host>s:%<port>i%<path>s", {
            scheme: request.fetch(:scheme) { connection[:scheme] },
            host: request.fetch(:hostname) { connection[:hostname] },
            port: request.fetch(:port) { connection[:port] },
            path: request.fetch(:path) { connection[:path] }
          }))
          uri.query = request.fetch(:query) { connection[:query] }

          Aikido::Zen::Scanners::SSRFScanner::Request.new(
            verb: request.fetch(:method) { connection[:method] },
            uri: uri,
            headers: connection[:headers].to_h.merge(request[:headers].to_h)
          )
        end

        def request(params = {}, *)
          request = Extensions.build_request(@data, params)

          # Store the request information so the DNS sinks can pick it up.
          if (context = Aikido::Zen.current_context)
            prev_request = context["ssrf.request"]
            context["ssrf.request"] = request
          end

          SINK.scan(
            connection: Aikido::Zen::OutboundConnection.from_uri(request.uri),
            request: request,
            operation: "request"
          )

          response = super

          Aikido::Zen::Scanners::SSRFScanner.track_redirects(
            request: request,
            response: Aikido::Zen::Scanners::SSRFScanner::Response.new(
              status: response.status,
              headers: response.headers.to_h
            )
          )

          response
        rescue ::Excon::Error::Socket => err
          # Excon wraps errors inside the lower level layer. This only happens
          # to our scanning exceptions when a request is using RedirectFollower,
          # so we unwrap them when it happens so host apps can handle errors
          # consistently.
          raise err.cause if err.cause.is_a?(Aikido::Zen::UnderAttackError)
          raise
        ensure
          context["ssrf.request"] = prev_request if context
        end
      end

      module RedirectFollowerExtensions
        def response_call(data)
          if (response = data[:response])
            Aikido::Zen::Scanners::SSRFScanner.track_redirects(
              request: Extensions.build_request(data, {}),
              response: Aikido::Zen::Scanners::SSRFScanner::Response.new(
                status: response[:status],
                headers: response[:headers]
              )
            )
          end

          super
        end
      end
    end
  end
end

::Excon::Connection.prepend(Aikido::Zen::Sinks::Excon::Extensions)
::Excon::Middleware::RedirectFollower.prepend(Aikido::Zen::Sinks::Excon::RedirectFollowerExtensions)
