# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::SocketTest < ActiveSupport::TestCase
  include SinkAttackHelpers

  # We can't easily stub C code to test the socket connections, and particularly
  # things like testing IMDS addresses would require the tests to be running in
  # a network that can actually resolve 169.254.169.254. So the tests here are a
  # little contrived and not as high level as we'd like, but rather just test
  # the scanning behavior in isolation, off of a stubbed "socket" object.
  def build_socket(name, port, address_family: "AF_INET")
    numeric_address = @stubbed_dns.fetch(name, name)

    socket = Minitest::Mock.new(Object.new)
    socket.expect :peeraddr, [address_family, port, numeric_address, numeric_address], [:numeric]
    socket.expect :instance_of?, true, [TCPSocket]

    Aikido::Zen::Sinks::Socket::Helpers.scan(name, socket, "open")

    assert_mock socket

    socket
  end

  setup { @stubbed_dns = {} }

  test "if socket is not exactly a TCPSocket it should skip the scan" do
    socket = Minitest::Mock.new(Object.new)
    socket.expect :instance_of?, false, [TCPSocket]

    Aikido::Zen::Sinks::Socket::Helpers.scan(name, socket, "open")

    assert_mock socket
  end

  test "scanning does not interfere with sockets normally" do
    @stubbed_dns["example.com"] = "1.2.3.4"

    refute_attack do
      build_socket("example.com", 80)
    end
  end

  test "scanning will detect stored SSRFs against IMDS addresses" do
    @stubbed_dns["trust-me.com"] = "169.254.169.254"

    assert_attack Aikido::Zen::Attacks::StoredSSRFAttack do
      build_socket("trust-me.com", 443)
    end
  end

  def build_request_to(uri)
    Aikido::Zen::Scanners::SSRFScanner::Request.new(
      verb: "GET",
      uri: URI(uri),
      headers: {}
    )
  end

  test "scanning will detect SSRFs if the socket is for a user-supplied hostname used for an HTTP request and it resolves to a dangerous address" do
    set_context_from_request_to "/?host=trust-me.com"

    Aikido::Zen.current_context["ssrf.request"] = build_request_to("https://trust-me.com/im-safe")

    @stubbed_dns["trust-me.com"] = "10.0.0.1"

    assert_attack Aikido::Zen::Attacks::SSRFAttack do
      build_socket("trust-me.com", 443)
    end
  end

  test "scanning will not consider it an SSRF if the socket is for a user-supplied hostname used for an HTTP request that does not resolve to a dangerous address" do
    set_context_from_request_to "/?search=google.com"

    Aikido::Zen.current_context["ssrf.request"] = build_request_to("https://google.com/search?q=foo")

    @stubbed_dns["google.com"] = "1.2.3.4"

    refute_attack do
      build_socket("google.com", 443)
    end
  end
end
