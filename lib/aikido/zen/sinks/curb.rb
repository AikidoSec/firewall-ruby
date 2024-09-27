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
        def self.wrap_request(curl)
          Aikido::Zen::HTTP::OutboundRequest.new(
            verb: nil, # Curb hides this by directly setting an option in C
            uri: URI(curl.url),
            headers: curl.headers
          )
        end

        def self.wrap_response(curl)
          # Curb made an… interesting choice by not parsing the response headers
          # and forcing users to do this manually if they need to look at them.
          _, *headers = curl.header_str.split(/[\r\n]+/).map(&:strip)
          headers = headers.flat_map { |str| str.scan(/\A(\S+): (.+)\z/) }.to_h

          Aikido::Zen::HTTP::OutboundResponse.new(
            status: curl.status.to_i,
            headers: headers
          )
        end

        def perform
          wrapped_request = Extensions.wrap_request(self)

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

          response
        end
      end
    end
  end
end

::Curl::Easy.prepend(Aikido::Zen::Sinks::Curl::Extensions)
