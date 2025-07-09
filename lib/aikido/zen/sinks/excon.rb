# frozen_string_literal: true

require_relative "../scanners/ssrf_scanner"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module Excon
      def self.load_sinks!
        ::Excon::Connection.prepend(ConnectionExtensions)
        ::Excon::Middleware::RedirectFollower.prepend(RedirectFollowerExtensions)
      end

      SINK = Sinks.add("excon", scanners: [
        Scanners::SSRFScanner,
        OutboundConnectionMonitor
      ])

      module Helpers
        def self.build_request(connection, request)
          uri = URI(format("%<scheme>s://%<host>s:%<port>i%<path>s", {
            scheme: request.fetch(:scheme) { connection[:scheme] },
            host: request.fetch(:hostname) { connection[:hostname] },
            port: request.fetch(:port) { connection[:port] },
            path: request.fetch(:path) { connection[:path] }
          }))
          uri.query = request.fetch(:query) { connection[:query] }

          Scanners::SSRFScanner::Request.new(
            verb: request.fetch(:method) { connection[:method] },
            uri: uri,
            headers: connection[:headers].to_h.merge(request[:headers].to_h)
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

      module ConnectionExtensions
        extend Sinks::DSL

        sink_around :request do |super_call, params = {}|
          request = Helpers.build_request(@data, params)

          # Store the request information so the DNS sinks can pick it up.
          context = Aikido::Zen.current_context
          if context
            prev_request = context["ssrf.request"]
            context["ssrf.request"] = request
          end

          connection = OutboundConnection.from_uri(request.uri)

          Helpers.scan(request, connection, "request")

          response = super_call.call

          Scanners::SSRFScanner.track_redirects(
            request: request,
            response: Scanners::SSRFScanner::Response.new(
              status: response.status,
              headers: response.headers.to_h
            )
          )

          response
        rescue Sinks::DSL::PresafeError => err
          outer_cause = err.cause
          case outer_cause
          when ::Excon::Error::Socket
            inner_cause = outer_cause.cause
            # Excon wraps errors inside the lower level layer. This only happens
            # to our scanning exceptions when a request is using RedirectFollower,
            # so we unwrap them when it happens so host apps can handle errors
            # consistently.
            raise inner_cause if inner_cause.is_a?(Aikido::Zen::UnderAttackError)
          end
          raise
        ensure
          context["ssrf.request"] = prev_request if context
        end
      end

      module RedirectFollowerExtensions
        extend Sinks::DSL

        sink_before :response_call do |datum|
          response = datum[:response]

          # Code coverage is disabled here because the else clause is a no-op,
          # so there is nothing to cover.
          # :nocov:
          if !response.nil?
            Scanners::SSRFScanner.track_redirects(
              request: Helpers.build_request(datum, {}),
              response: Scanners::SSRFScanner::Response.new(
                status: response[:status],
                headers: response[:headers]
              )
            )
          else
            # empty
          end
          # :nocov:
        end
      end
    end
  end
end

Aikido::Zen::Sinks::Excon.load_sinks!
