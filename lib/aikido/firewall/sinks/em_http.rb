# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Firewall
  module Sinks
    module EventMachine
      module HttpRequest
        SINK = Sinks.add("em-http-request", scanners: [
          Aikido::Firewall::OutboundConnectionMonitor
        ])

        module Extensions
          def activate_connection(*)
            conn = Aikido::Agent::OutboundConnection.new(
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
  .prepend(Aikido::Firewall::Sinks::EventMachine::HttpRequest::Extensions)
