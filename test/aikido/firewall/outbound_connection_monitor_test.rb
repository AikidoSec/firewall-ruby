# frozen_string_literal: true

require "test_helper"

class Aikido::Firewall::OutboundConnectionMonitorTest < ActiveSupport::TestCase
  test "tells the agent to track the connection" do
    conn = Aikido::Agent::OutboundConnection.new(host: "example.com", port: 443)

    agent = Minitest::Mock.new
    agent.expect :track_outbound, nil, [conn]

    Aikido.stub_const(:Agent, agent) do
      Aikido::Firewall::OutboundConnectionMonitor.call(connection: conn)

      assert_mock agent
    end
  end

  test "returns nil" do
    conn = Aikido::Agent::OutboundConnection.new(host: "example.com", port: 443)
    assert_nil Aikido::Firewall::OutboundConnectionMonitor.call(connection: conn)
  end
end
