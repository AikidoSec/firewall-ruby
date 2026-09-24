# frozen_string_literal: true

require "test_helper"
require "aikido/zen/ip_lists/address"

class Aikido::Zen::IPLists::AddressTest < ActiveSupport::TestCase
  test ".parse returns an ipv4 Address for a String" do
    address = Aikido::Zen::IPLists::Address.parse("1.2.3.4")

    assert_equal :ipv4, address.family
    assert_equal 0x01020304, address.to_i
  end

  test ".parse returns an ipv4 Address for an IPAddr" do
    address = Aikido::Zen::IPLists::Address.parse(IPAddr.new("1.2.3.4"))

    assert_equal :ipv4, address.family
    assert_equal 0x01020304, address.to_i
  end

  test ".parse returns an ipv6 Address for a String" do
    address = Aikido::Zen::IPLists::Address.parse("2001:db8::1")

    assert_equal :ipv6, address.family
    assert_equal IPAddr.new("2001:db8::1").to_i, address.to_i
  end

  test ".parse returns an ipv6 Address for an IPAddr" do
    address = Aikido::Zen::IPLists::Address.parse(IPAddr.new("2001:db8::1"))

    assert_equal :ipv6, address.family
    assert_equal IPAddr.new("2001:db8::1").to_i, address.to_i
  end

  test ".parse returns an ipv4 Address for an ipv4-mapped ipv6 IPAddr" do
    address = Aikido::Zen::IPLists::Address.parse(IPAddr.new("::ffff:1.2.3.4"))

    assert_equal :ipv4, address.family
    assert_equal 0x01020304, address.to_i
  end

  test ".parse returns nil for an unparseable string" do
    assert_nil Aikido::Zen::IPLists::Address.parse("not an ip address")
  end

  test ".parse returns nil for nil" do
    assert_nil Aikido::Zen::IPLists::Address.parse(nil)
  end

  test ".parse raises for anything other than a String, IPAddr, or nil" do
    assert_raises(ArgumentError) { Aikido::Zen::IPLists::Address.parse(1234) }
  end

  test ".parse raises when the native address is neither ipv4 nor ipv6" do
    native_ip = IPAddr.new("1.2.3.4")

    native_ip.stub :ipv4?, false do
      native_ip.stub :ipv6?, false do
        Aikido::Zen::Helpers.stub :nativize_ip, native_ip do
          assert_raises(ArgumentError) { Aikido::Zen::IPLists::Address.parse("1.2.3.4") }
        end
      end
    end
  end
end
