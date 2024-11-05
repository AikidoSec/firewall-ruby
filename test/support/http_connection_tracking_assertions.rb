# frozen_string_literal: true

require "ostruct"

# Assertion to track our outbound connection tracking is working as expected
# around a block. Used by Sink tests that perform network connections.
module HTTPConnectionTrackingAssertions
  def assert_tracks_outbound_to(host, port, &block)
    hosts = Aikido::Zen.collector.hosts

    assert_difference "hosts.size", +1 do
      2.times(&block) # run the block twice to ensure we only count it once.
    end

    expected = Aikido::Zen::OutboundConnection.new(host: host, port: port)
    assert_includes hosts, expected
  end

  def refute_outbound_connection_to(host, port, &block)
    hosts = Aikido::Zen.collector.hosts

    assert_no_difference "hosts.size" do
      yield
    end

    expected = Aikido::Zen::OutboundConnection.new(host: host, port: port)
    refute_includes hosts, expected
  end
end
