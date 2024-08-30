# frozen_string_literal: true

# Assertion to track our outbound connection tracking is working as expected
# around a block. Used by Sink tests that perform network connections.
module HTTPConnectionTrackingAssertions
  def stub_outbound(host, port)
    Aikido::Agent::OutboundConnection.new(host: host, port: port)
  end

  def assert_tracks_outbound_to(host, port, &block)
    outbounds = Aikido::Agent.send(:runner).stats.outbound_connections

    assert_difference -> { outbounds.size }, +1 do
      2.times(&block) # run the block twice to ensure we only count it once.
    end

    assert_includes outbounds, stub_outbound(host, port)
  end
end
