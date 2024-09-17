# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::OutboundConnectionMonitorTest < ActiveSupport::TestCase
  setup do
    @monitor = Aikido::Zen::OutboundConnectionMonitor
  end

  test "tells the agent to track the connection" do
    conn = Aikido::Zen::OutboundConnection.new(host: "example.com", port: 443)

    agent = Minitest::Mock.new
    agent.expect :track_outbound, nil, [conn]

    Aikido.stub_const(:Zen, agent) do
      @monitor.call(connection: conn)

      assert_mock agent
    end
  end

  test "returns nil" do
    conn = Aikido::Zen::OutboundConnection.new(host: "example.com", port: 443)
    assert_nil @monitor.call(connection: conn)
  end
end
