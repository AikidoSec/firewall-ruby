# frozen_string_literal: true

require "ostruct"

# Assertion to track our outbound connection tracking is working as expected
# around a block. Used by Sink tests that perform network connections.
module HTTPConnectionTrackingAssertions
  def assert_tracks_outbound_to(host, port, &block)
    stats = Aikido::Agent::Stats.new
    fake_runner = OpenStruct.new(stats: stats)

    Aikido::Agent.stub(:runner, fake_runner) do
      assert_difference -> { stats.outbound_connections.size }, +1 do
        2.times(&block) # run the block twice to ensure we only count it once.
      end

      expected = Aikido::Agent::OutboundConnection.new(host: host, port: port)
      assert_includes stats.outbound_connections, expected
    end
  end
end
