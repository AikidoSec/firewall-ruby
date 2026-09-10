# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Firewall::IPMatcherTest < ActiveSupport::TestCase
  test "matches IPv4 and IPv6 networks" do
    matcher = Aikido::Zen::Firewall::IPMatcher.new([
      "192.0.2.0/24",
      "2001:db8::/32"
    ])

    assert matcher.include?("192.0.2.255")
    refute matcher.include?("192.0.3.0")
    assert matcher.include?("2001:db8:ffff:ffff:ffff:ffff:ffff:ffff")
    refute matcher.include?("2001:db9::1")
  end

  test "sorts and summarizes contained and adjacent networks" do
    matcher = Aikido::Zen::Firewall::IPMatcher.new([
      "10.0.3.0/24",
      "10.0.1.0/24",
      "10.0.0.0/24",
      "10.0.2.0/24",
      "10.0.0.1",
      "2001:db8:0:3::/64",
      "2001:db8:0:1::/64",
      "2001:db8:0:0::/64",
      "2001:db8:0:2::/64"
    ])

    assert_equal 2, matcher.size
    assert matcher.include?("10.0.3.255")
    refute matcher.include?("10.0.4.0")
    assert matcher.include?("2001:db8:0:3:ffff:ffff:ffff:ffff")
    refute matcher.include?("2001:db8:0:4::")
  end

  test "merges adjacent networks at the end of each address space" do
    matcher = Aikido::Zen::Firewall::IPMatcher.new([
      "224.0.0.0/4",
      "240.0.0.0/4",
      "e000::/4",
      "f000::/4"
    ])

    assert_equal 2, matcher.size
    assert matcher.include?("255.255.255.255")
    refute matcher.include?("223.255.255.255")
    assert matcher.include?("ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff")
    refute matcher.include?("dfff:ffff:ffff:ffff:ffff:ffff:ffff:ffff")
  end

  test "ignores invalid networks and lookups" do
    matcher = Aikido::Zen::Firewall::IPMatcher.new([
      "192.0.2.0/24",
      "foobar",
      "0.a.0.0/32",
      "123.123.123.123/1999",
      ""
    ])

    assert_equal 1, matcher.size
    assert matcher.include?("192.0.2.1")
    refute matcher.include?("foobar")
    refute matcher.include?("")
    refute matcher.include?(nil)
  end

  test "supports Node IP matcher address forms" do
    matcher = Aikido::Zen::Firewall::IPMatcher.new([
      "192.0.2.1",
      "2001:db8::1",
      "fe80::/10"
    ])

    assert matcher.include?("192.0.2.1:80")
    assert matcher.include?("[2001:db8::1]:443")
    assert matcher.include?("2001:db8::1p443")
    assert matcher.include?("fe80::1%eth0")
    refute matcher.include?("fe80::1%")
  end

  test "optionally matches IPv4-mapped IPv6 addresses against IPv4 networks" do
    matcher = Aikido::Zen::Firewall::IPMatcher.new(["192.0.2.0/24"])

    refute matcher.include?("::ffff:192.0.2.1")
    assert matcher.include_with_mapped?("::ffff:192.0.2.1")
    assert matcher.include_with_mapped?("::ffff:c000:201")
    refute matcher.include_with_mapped?("::ffff:192.0.3.1")
  end
end
