# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Scanners::SSRF::PrivateIPCheckerTest < ActiveSupport::TestCase
  include StubsCurrentContext

  setup do
    @resolver = Minitest::Mock.new(Resolv::Hosts.new)
    @subject = Aikido::Zen::Scanners::SSRF::PrivateIPChecker.new(@resolver)
  end

  def assert_private(address)
    assert @subject.private?(address),
      "Expected #{address.inspect} to be considered private"
  end

  def refute_private(address)
    refute @subject.private?(address),
      "Expected #{address.inspect} not to be considered private"
  end

  test "resolves hosts that are defined in /etc/hosts" do
    assert_private "localhost"
  end

  test "if hosts the resolver resolves to an otherwise internal IP, it's private" do
    @resolver.expect :getaddresses, ["10.0.0.8"], ["data.myservice"]
    @resolver.expect :getaddresses, ["1.2.3.4"], ["external.myservice.com"]

    assert_private "data.myservice"
    refute_private "external.myservice.com"

    assert_mock @resolver
  end

  test "detects hostnames that have already been resolved and stored in the context" do
    current_context["dns.lookups"] = Aikido::Zen::Scanners::SSRF::DNSLookups.new
    current_context["dns.lookups"].add("harmless.com", "10.0.0.1")

    assert_private "harmless.com"
  end

  test "ignores hostnames that have been resolved and don't point to a private address" do
    current_context["dns.lookups"] = Aikido::Zen::Scanners::SSRF::DNSLookups.new
    current_context["dns.lookups"].add("example.com", "1.2.3.4")

    refute_private "example.com"
  end

  test "detects hostnames that previously resolved to an internal IP to mitigate TOCTOU attacks" do
    current_context["dns.lookups"] = Aikido::Zen::Scanners::SSRF::DNSLookups.new
    current_context["dns.lookups"].add("example.com", "1.2.3.4")
    current_context["dns.lookups"].add("example.com", "10.0.0.1")
    current_context["dns.lookups"].add("example.com", "1.2.3.4")

    assert_private "example.com"
  end

  test "does not fail if there's no current_context" do
    Aikido::Zen.current_context = nil

    refute_private "example.com"
  end

  test "ignores invalid input without errors" do
    refute_private nil
    refute_private ""
    refute_private "192"
  end

  test "detects loopback addresses" do
    assert_private "127.0.0.1"
    assert_private "::1"
  end

  test "detects _actually_ private (RFC 1918/RFC 4193) addresses" do
    # 10.0.0.0/8
    assert_private "10.0.0.0"
    assert_private "10.128.128.128"
    assert_private "10.255.255.255"
    refute_private "11.0.0.1"

    # 172.16.0.0/12
    assert_private "172.16.0.0"
    assert_private "172.24.128.128"
    assert_private "172.31.255.255"
    refute_private "172.32.0.0"

    # 192.168.0.0/16
    assert_private "192.168.0.0"
    assert_private "192.168.128.128"
    assert_private "192.168.255.255"
    refute_private "192.169.0.0"

    # fc00::/7
    assert_private "fc00::"
    assert_private "fc00:0000:0000:0000:0000:0000:0000:0000"
    assert_private "fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"
    refute_private "fe00::"
  end

  test "detects all special-use addresses from RFC 5735 as 'private' too" do
    # 0.0.0.0/8
    assert_private "0.0.0.0"
    assert_private "0.128.0.0"
    assert_private "0.255.255.255"
    refute_private "1.0.0.0"

    # 100.64.0.0/10
    assert_private "100.64.0.0"
    assert_private "100.96.0.0"
    assert_private "100.127.255.255"
    refute_private "100.63.255.255"
    refute_private "100.128.0.0"

    # 127.0.0.0/8
    assert_private "127.0.0.0"
    assert_private "127.128.0.0"
    assert_private "127.255.255.255"
    refute_private "126.255.255.255"
    refute_private "128.0.0.0"

    # 169.254.0.0/16
    assert_private "169.254.0.0"
    assert_private "169.254.128.0"
    assert_private "169.254.255.255"
    refute_private "169.253.255.255"
    refute_private "169.255.0.0"

    # 192.0.0.0/24
    assert_private "192.0.0.0"
    assert_private "192.0.0.128"
    assert_private "192.0.0.255"
    refute_private "191.255.255.255"
    refute_private "192.0.1.0"

    # 192.0.2.0/24
    assert_private "192.0.2.0"
    assert_private "192.0.2.128"
    assert_private "192.0.2.255"
    refute_private "192.0.1.255"
    refute_private "192.0.3.0"

    # 192.31.196.0/24
    assert_private "192.31.196.0"
    assert_private "192.31.196.128"
    assert_private "192.31.196.255"
    refute_private "192.31.195.255"
    refute_private "192.31.197.0"

    # 192.52.193.0/24
    assert_private "192.52.193.0"
    assert_private "192.52.193.128"
    assert_private "192.52.193.255"
    refute_private "192.52.192.255"
    refute_private "192.52.194.0"

    # 192.88.99.0/24
    assert_private "192.88.99.0"
    assert_private "192.88.99.128"
    assert_private "192.88.99.255"
    refute_private "192.88.98.255"
    refute_private "192.88.100.0"

    # 192.175.48.0/24
    assert_private "192.175.48.0"
    assert_private "192.175.48.128"
    assert_private "192.175.48.255"
    refute_private "192.175.47.255"
    refute_private "192.175.49.0"

    # 198.18.0.0/15
    assert_private "198.18.0.0"
    assert_private "198.18.128.0"
    assert_private "198.19.255.255"
    refute_private "198.17.255.255"
    refute_private "198.20.0.0"

    # 198.51.100.0/24
    assert_private "198.51.100.0"
    assert_private "198.51.100.128"
    assert_private "198.51.100.255"
    refute_private "198.51.99.255"
    refute_private "198.51.101.0"

    # 203.0.113.0/24
    assert_private "203.0.113.0"
    assert_private "203.0.113.128"
    assert_private "203.0.113.255"
    refute_private "203.0.112.255"
    refute_private "203.0.114.0"

    # 240.0.0.0/4
    assert_private "240.0.0.0"
    assert_private "240.128.0.0"
    assert_private "255.255.255.255"

    # 224.0.0.0/4
    assert_private "224.0.0.0"
    assert_private "224.128.0.0"
    assert_private "239.255.255.255"
    refute_private "223.255.255.255"

    # ::/128
    assert_private "::"
    assert_private "::0"

    # fe80::/10
    assert_private "fe80::"
    assert_private "fe80::1"
    assert_private "fe80:ffff:ffff:ffff:ffff:ffff:ffff:ffff"
    refute_private "fe7f:ffff:ffff:ffff:ffff:ffff:ffff:ffff"

    # ::ffff:127.0.0.1/128
    assert_private "::ffff:127.0.0.1"
  end
end
