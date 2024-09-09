# frozen_string_literal: true

require_relative "../sink"
require_relative "../outbound_connection_monitor"

module Aikido::Zen
  module Sinks
    module Excon
      SINK = Sinks.add("excon", scanners: [
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

        def request(params = {}, *)
          conn = Extensions.build_outbound(@data, params)
          SINK.scan(connection: conn, operation: "request")

          super
        end
      end
    end
  end
end

::Excon::Connection.prepend(Aikido::Zen::Sinks::Excon::Extensions)
