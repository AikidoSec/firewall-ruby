# frozen_string_literal: true

require_relative "../agent"

module Aikido::Firewall
  # This simple callable follows the Scanner API so that it can be injected into
  # any Sink that wraps an HTTP library, and lets us keep track of any hosts to
  # which the app communicates over HTTP.
  module OutboundConnectionMonitor
    # This simply reports the connection to the Agent, and always returns +nil+
    # as it's not scanning for any particular attack.
    #
    # @param connection [Aikido::Agent::OutboundConnection]
    # @return [nil]
    def self.call(connection:, **)
      Aikido::Agent.track_outbound(connection)

      nil
    end
  end
end
