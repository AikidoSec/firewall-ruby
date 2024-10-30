# frozen_string_literal: true

require "ostruct"

# Assertion to track our outbound connection tracking is working as expected
# around a block. Used by Sink tests that perform network connections.
module HTTPConnectionTrackingAssertions
  def assert_tracks_outbound_to(host, port, &block)
    stats = Aikido::Zen::Stats.new
    fake_agent = FakeAgent.new(stats)

    Aikido::Zen.stub(:agent, fake_agent) do
      assert_difference "stats.outbound_connections.size", +1 do
        2.times(&block) # run the block twice to ensure we only count it once.
      end

      expected = Aikido::Zen::OutboundConnection.new(host: host, port: port)
      assert_includes stats.outbound_connections, expected
    end
  end

  FakeAgent = Struct.new(:stats) do
    %w[scan attack request outbound].each do |key|
      define_method(:"track_#{key}") { |obj| stats.send(:"add_#{key}", obj) }
    end
  end
end
