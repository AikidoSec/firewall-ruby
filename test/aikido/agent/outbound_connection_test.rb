# frozen_string_literal: true

require "test_helper"

class Aikido::Agent::OutboundConnectionTest < ActiveSupport::TestCase
  test "two connections are equal if their host and port are equal" do
    c1 = Aikido::Agent::OutboundConnection.new(host: "example.com", port: 80)
    c2 = Aikido::Agent::OutboundConnection.new(host: "example.com", port: 80)
    c3 = Aikido::Agent::OutboundConnection.new(host: "example.com", port: 443)
    c4 = Aikido::Agent::OutboundConnection.new(host: "example.org", port: 80)

    assert_equal c1, c2
    refute_equal c1, c3
    refute_equal c1, c4
  end

  test "connections can be used as hash keys" do
    c1 = Aikido::Agent::OutboundConnection.new(host: "example.com", port: 443)
    c2 = Aikido::Agent::OutboundConnection.new(host: "example.com", port: 443)

    counter = Hash.new(0)
    counter[c1] += 2

    assert_equal 2, counter[c2]
  end

  test "#as_json includes hostname and port" do
    conn = Aikido::Agent::OutboundConnection.new(host: "example.com", port: 443)
    assert_equal({hostname: "example.com", port: 443}, conn.as_json)
  end
end
