# frozen_string_literal: true

require "test_helper"
require "aikido/zen/ip_lists/address"

class Aikido::Zen::IPLists::AddressTest < ActiveSupport::TestCase
  test "parses an ipv4 string" do
    address = Aikido::Zen::IPLists.parse_ip("1.2.3.4")

    assert_equal :ipv4, address.family
    assert_equal 0x01020304, address.to_i
  end

  test "parses an ipv4 IPAddr" do
    address = Aikido::Zen::IPLists.parse_ip(IPAddr.new("1.2.3.4"))

    assert_equal :ipv4, address.family
    assert_equal 0x01020304, address.to_i
  end

  test "parses an ipv6 string" do
    address = Aikido::Zen::IPLists.parse_ip("2001:db8::1")

    assert_equal :ipv6, address.family
    assert_equal IPAddr.new("2001:db8::1").to_i, address.to_i
  end

  test "parses an ipv6 IPAddr" do
    address = Aikido::Zen::IPLists.parse_ip(IPAddr.new("2001:db8::1"))

    assert_equal :ipv6, address.family
    assert_equal IPAddr.new("2001:db8::1").to_i, address.to_i
  end

  test "parses an ipv4-mapped ipv6 IPAddr as ipv4" do
    address = Aikido::Zen::IPLists.parse_ip(IPAddr.new("::ffff:1.2.3.4"))

    assert_equal :ipv4, address.family
    assert_equal 0x01020304, address.to_i
  end

  test "returns nil for an unparseable string" do
    assert_nil Aikido::Zen::IPLists.parse_ip("not an ip address")
  end

  test "returns nil for nil" do
    assert_nil Aikido::Zen::IPLists.parse_ip(nil)
  end

  test "raises for anything other than a String, IPAddr, or nil" do
    assert_raises(ArgumentError) { Aikido::Zen::IPLists.parse_ip(1234) }
  end
end
