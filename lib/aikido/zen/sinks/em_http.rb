# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module EventMachine
      module HttpRequest
        SINK = Sinks.add("em-http-request", scanners: [
          Aikido::Zen::OutboundConnectionMonitor
        ])

        module Extensions
          def activate_connection(*)
            conn = Aikido::Zen::OutboundConnection.new(
              host: connopts.host, port: connopts.port
            )
            SINK.scan(connection: conn, operation: "request")

            super
          end
        end
      end
    end
  end
end

::EventMachine::HttpConnection
  .prepend(Aikido::Zen::Sinks::EventMachine::HttpRequest::Extensions)
