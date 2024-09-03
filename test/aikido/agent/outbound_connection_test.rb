# frozen_string_literal: true

require "test_helper"

class Aikido::Agent::OutboundConnectionTest < ActiveSupport::TestCase
  test "can be initialized from a URI" do
    uri = URI("http://example.net:4567/test")
    conn = Aikido::Agent::OutboundConnection.from_uri(uri)

    assert_equal "example.net", conn.host
    assert_equal 4567, conn.port
  end

  test "gets the correct default port for HTTP/HTTPS URIs" do
    http_conn = Aikido::Agent::OutboundConnection.from_uri(URI("http://example.com"))
    assert_equal 80, http_conn.port

    https_conn = Aikido::Agent::OutboundConnection.from_uri(URI("https://example.com"))
    assert_equal 443, https_conn.port
  end

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
