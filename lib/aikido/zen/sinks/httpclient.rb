# frozen_string_literal: true

require_relative "../scanners/ssrf_scanner"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module HTTPClient
      SINK = Sinks.add("httpclient", scanners: [
        Scanners::SSRFScanner,
        OutboundConnectionMonitor
      ])

      module Helpers
        def self.wrap_request(req)
          Scanners::SSRFScanner::Request.new(
            verb: req.http_header.request_method,
            uri: req.http_header.request_uri,
            headers: req.headers
          )
        end

        def self.wrap_response(resp)
          # Code coverage is disabled here because `do_get_header` is not called,
          # because WebMock does not mock it.
          # :nocov:
          Scanners::SSRFScanner::Response.new(
            status: resp.http_header.status_code,
            headers: resp.headers
          )
          # :nocov:
        end

        def self.scan(request, connection, operation)
          SINK.scan(
            request: request,
            connection: connection,
            operation: operation
          )
        end

        def self.sink(req, &block)
          wrapped_request = wrap_request(req)
          connection = OutboundConnection.from_uri(req.http_header.request_uri)

          # Store the request information so the DNS sinks can pick it up.
          context = Aikido::Zen.current_context
          if context
            prev_request = context["ssrf.request"]
            context["ssrf.request"] = wrapped_request
          end

          scan(wrapped_request, connection, "request")

          yield
        ensure
          context["ssrf.request"] = prev_request if context
        end
      end

      def self.load_sinks!
        if Aikido::Zen.satisfy "httpclient", ">= 2.0"
          require "httpclient"

          ::HTTPClient.class_eval do
            extend Sinks::DSL

            private

            sink_around :do_get_block do |original_call, req|
              Helpers.sink(req, &original_call)
            end

            sink_around :do_get_stream do |original_call, req|
              Helpers.sink(req, &original_call)
            end

            sink_after :do_get_header do |_result, req, res, _sess|
              # Code coverage is disabled here because `do_get_header` is not called,
              # because WebMock does not mock it.
              # :nocov:
              Scanners::SSRFScanner.track_redirects(
                request: Helpers.wrap_request(req),
                response: Helpers.wrap_response(res)
              )
              # :nocov:
            end
          end
        end
      end
    end
  end
end

Aikido::Zen::Sinks::HTTPClient.load_sinks!
